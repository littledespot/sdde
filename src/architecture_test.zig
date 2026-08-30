const std = @import("std");
const bootstrap_root_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_root_registry_service = @import("application/bootstrap_root_registry_service.zig");
const workflow_registry = @import("domain/workflow_registry.zig");
const workflow_registry_service = @import("application/workflow_definition_registry_service.zig");
const toolchain = @import("domain/toolchain.zig");

test "every action imports only standard domain and port modules" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);

    var walker = try actions.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) {
            continue;
        }

        const source = try entry.dir.readFileAlloc(
            io,
            entry.basename,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        try expectAllowedActionImports(source);
    }
}

test "bootstrap orchestrator imports only binding and result contracts" {
    const source = @embedFile("application/bootstrap_orchestrator.zig");
    try expectAbsent(source, "/actions/");
    try expectAbsent(source, "/adapters/");
    try expectAbsent(source, "std.Io");
}

test "public root does not re-export ports or infrastructure adapters" {
    const source = @embedFile("root.zig");
    try expectAbsent(source, "adapters/");
    try expectAbsent(source, "ports/");
    try expectAbsent(source, "bootstrap_roots");
}

test "validated bootstrap registry authority is opaque" {
    switch (@typeInfo(bootstrap_root_registry.BootstrapRootRegistry)) {
        .@"opaque" => {},
        else => return error.RegistryAuthorityMustBeOpaque,
    }
    switch (@typeInfo(bootstrap_root_registry.ConfiguredBaseRootCapability)) {
        .@"opaque" => {},
        else => return error.RootCapabilityMustBeOpaque,
    }

    const service_source = @embedFile("application/bootstrap_root_registry_service.zig");
    try expectAbsent(service_source, "bootstrap_roots");
    try expectAbsent(service_source, "ValidatedConfiguredRoot");

    const inspector_source = @embedFile("adapters/filesystem/bootstrap_root_inspector.zig");
    try expectAbsent(inspector_source, "workspacePathPolicy");

    const init_type = @typeInfo(@TypeOf(
        bootstrap_root_registry_service.BootstrapRootRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);
    try std.testing.expect(init_type.params[0].type.? == *bootstrap_root_registry.Owner);
}

test "configuration domain ownership is independent of the JSON parser" {
    const source = @embedFile("domain/config.zig");
    try expectAbsent(source, "std.json.Parsed");
    try expectAbsent(source, "PublicError");
    try expectAbsent(source, "Registry");
}

test "workflow compiler and service preserve their authority boundaries" {
    switch (@typeInfo(workflow_registry.ValidatedWorkflowDefinitionRegistry)) {
        .@"opaque" => {},
        else => return error.WorkflowRegistryAuthorityMustBeOpaque,
    }
    const compiler = @embedFile("actions/workflow/compile_workflow_graphs.zig");
    try expectAbsent(compiler, "adapters/");
    try expectAbsent(compiler, "filesystem");
    try expectAbsent(compiler, "std.Io");

    const service = @embedFile("application/workflow_definition_registry_service.zig");
    try expectAbsent(service, "Inventory");
    try expectAbsent(service, "RawDefinition");
    const init_type = @typeInfo(@TypeOf(
        workflow_registry_service.WorkflowDefinitionRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);

    const domain = @embedFile("domain/bootstrap_root_registry.zig");
    const adapter = @embedFile("adapters/filesystem/workflow_authority_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, domain, "bindWorkflowAuthorityAdapter") != null);
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(
        adapter,
        "bindWorkflowAuthorityAdapter",
    ));

    const parser_action = @embedFile("actions/workflow/parse_workflow_definitions.zig");
    try std.testing.expect(std.mem.indexOf(u8, parser_action, "workflow_definition_parser.zig") != null);
    try expectAbsent(parser_action, "std.json");
    try expectAbsent(parser_action, "bounded_yaml_syntax");
    try expectAbsent(parser_action, "/adapters/");
    const parser_adapter = @embedFile("adapters/parsers/workflow_definitions.zig");
    try std.testing.expect(std.mem.indexOf(u8, parser_adapter, "bounded_yaml_syntax") != null);
    try std.testing.expect(std.mem.indexOf(u8, parser_adapter, "workflow_definition_parser.zig") != null);
    const workflow_domain = @embedFile("domain/workflow_registry.zig");
    try expectAbsent(workflow_domain, "std.json");
    try expectAbsent(workflow_domain, "bounded_yaml_syntax");

    const capture = @embedFile("actions/workflow/capture_workflow_definitions.zig");
    const budget_index = std.mem.indexOf(u8, capture, "validateCaptureBudget") orelse return error.MissingWorkflowCaptureBudget;
    const read_index = std.mem.indexOf(u8, capture, "source.capture") orelse return error.MissingWorkflowCapture;
    try std.testing.expect(budget_index < read_index);
}

test "toolchain safety authority is opaque and path handoff has one adapter consumer" {
    switch (@typeInfo(toolchain.ValidToolchain)) {
        .@"opaque" => {},
        else => return error.ValidToolchainMustBeOpaque,
    }
    const domain = @embedFile("domain/bootstrap_root_registry.zig");
    const adapter = @embedFile("adapters/filesystem/toolchain_authority_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, domain, "bindToolchainAuthorityAdapter") != null);
    try std.testing.expectEqual(@as(usize, 3), countOccurrences(adapter, "bindToolchainAuthorityAdapter"));
    const service = @embedFile("application/toolchain_service.zig");
    try expectAbsent(service, "RawDocument");
    try expectAbsent(service, "std.Io");
    const runner = @embedFile("application/bootstrap_runner.zig");
    try expectAbsent(runner, "invokeBootstrapToolchain");
    const capture = @embedFile("actions/toolchain/capture_toolchain_presets.zig");
    const budget_index = std.mem.indexOf(u8, capture, "validateCaptureBudget") orelse return error.MissingCaptureBudget;
    const read_index = std.mem.indexOf(u8, capture, "capturePreset") orelse return error.MissingPresetCapture;
    try std.testing.expect(budget_index < read_index);
    const parser = @embedFile("actions/toolchain/parse_toolchain_documents.zig");
    try expectAbsent(parser, "validateCaptureBudget");
}

test "feature log paths have one opaque artifact authority and one sink consumer" {
    const artifacts = @import("domain/workflow_artifact_registry.zig");
    switch (@typeInfo(artifacts.WorkflowArtifactRegistry)) {
        .@"opaque" => {},
        else => return error.WorkflowArtifactRegistryMustBeOpaque,
    }
    const root_domain = @embedFile("domain/bootstrap_root_registry.zig");
    const artifact_domain = @embedFile("domain/workflow_artifact_registry.zig");
    const sink = @embedFile("adapters/filesystem/feature_log_sink.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(root_domain, "bindSpecsArtifactRegistry("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(artifact_domain, "bindSpecsArtifactRegistry("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(sink, "bindFeatureLogSinkAdapter"));
    try expectAbsent(root_domain, "physical_identity: ?roots.PhysicalDirectoryIdentity");
    try expectAbsent(sink, "createDirPathOpen");
}

test "feature logging lifecycle coordinates bindings without filesystem authority" {
    const lifecycle = @embedFile("application/feature_log_runtime_lifecycle.zig");
    try expectAbsent(lifecycle, "/adapters/");
    try expectAbsent(lifecycle, "std.Io");
    try expectAbsent(lifecycle, "createDir");
    const composition = @embedFile("composition/root.zig");
    try std.testing.expect(std.mem.indexOf(u8, composition, "services.logs.barrier()") != null);
    try expectAbsent(composition, "feature_log_lifecycle.Lifecycle");
    try expectAbsent(composition, "unbound_telemetry_barrier");
}

test "active feature logging concrete assembly remains in composition" {
    const assembly = @embedFile("composition/active_feature_log_runtime.zig");
    try std.testing.expect(std.mem.indexOf(u8, assembly, "adapters/filesystem/feature_log_sink.zig") != null);
    const service = @embedFile("application/log_service.zig");
    try expectAbsent(service, "/adapters/");
    try expectAbsent(service, "std.Io");
}

test "generic workflow engine is capability free and workflow-name agnostic" {
    const orchestrator = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    try expectAbsent(orchestrator, "std.Io");
    try expectAbsent(orchestrator, "\"specify\"");
    try expectAbsent(orchestrator, "\"implement\"");
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try expectAbsent(runner, "\"specify\"");
    try expectAbsent(runner, "\"implement\"");
    try expectAbsent(runner, "/adapters/");
}

test "feature service filenames and headings end in Service" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var features = try std.Io.Dir.cwd().openDir(io, "design/features", .{ .iterate = true });
    defer features.close(io);

    var iterator = features.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or
            !std.mem.startsWith(u8, entry.name, "F") or
            !std.mem.endsWith(u8, entry.name, ".md"))
        {
            continue;
        }

        try std.testing.expect(std.mem.endsWith(u8, entry.name, "Service.md"));
        const source = try features.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        const heading_end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
        const heading = std.mem.trimEnd(u8, source[0..heading_end], "\r");
        try std.testing.expect(std.mem.endsWith(u8, heading, "Service"));
    }
}

fn expectAbsent(source: []const u8, forbidden: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, source, forbidden) == null);
}

fn expectAllowedActionImports(source: []const u8) !void {
    const prefix = "@import(\"";
    var remaining = source;
    while (std.mem.indexOf(u8, remaining, prefix)) |import_start| {
        const path_start = import_start + prefix.len;
        const path_end = std.mem.indexOfScalarPos(u8, remaining, path_start, '"') orelse {
            return error.UnterminatedImport;
        };
        const path = remaining[path_start..path_end];
        try std.testing.expect(
            std.mem.eql(u8, path, "std") or
                std.mem.eql(u8, path, "builtin") or
                std.mem.startsWith(u8, path, "../../domain/") or
                std.mem.startsWith(u8, path, "../../ports/"),
        );
        remaining = remaining[path_end + 1 ..];
    }
}

fn countOccurrences(source: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var remaining = source;
    while (std.mem.indexOf(u8, remaining, needle)) |index| {
        count += 1;
        remaining = remaining[index + needle.len ..];
    }
    return count;
}
