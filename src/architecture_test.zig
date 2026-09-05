const std = @import("std");
const bootstrap_root_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_root_registry_service = @import("application/bootstrap_root_registry_service.zig");
const workflow_registry = @import("domain/workflow_registry.zig");
const workflow_registry_service = @import("application/workflow_definition_registry_service.zig");
const toolchain_safety = @import("domain/toolchain_safety.zig");
const llm_provider_registry = @import("domain/llm_provider_registry.zig");
const repository_model_allowlist = @import("domain/repository_model_allowlist.zig");
const model_request_identity = @import("domain/model_request_identity.zig");
const model_attempt_accounting = @import("domain/model_attempt_accounting.zig");
const llm_provider_operation = @import("domain/llm_provider_operation.zig");
const llm_provider_interface = @import("ports/llm_provider_interface.zig");
const llm_provider_registry_service = @import("application/llm_provider_registry_service.zig");
const derive_provider_requirement = @import("actions/provider/derive_provider_requirement.zig");
const workflow_execution = @import("domain/workflow_execution.zig");

test "transaction ledger candidates are opaque capability-free snapshots with shared owner identities" {
    const identity = @import("domain/transaction_identity.zig");
    const ledger = @import("domain/transaction_id_ledger.zig");
    try std.testing.expect(@typeInfo(ledger.Ledger) == .@"opaque");
    try std.testing.expect(@typeInfo(ledger.Owner) == .@"opaque");
    try std.testing.expect(@typeInfo(identity.StorageOwner) == .@"struct");
    try std.testing.expectEqual(@as(usize, 2), @typeInfo(identity.StorageOwner).@"struct".fields.len);
    try std.testing.expect(!@hasField(identity.StorageOwner, "project"));
    try std.testing.expect(@FieldType(identity.StorageOwner, "feature_id") == @import("domain/feature_identity.zig").FeatureId);
    try std.testing.expect(@FieldType(identity.StorageOwner, "workflow_artifact_registry_state_id") == @import("domain/workflow_artifact_registry.zig").StateId);
    try std.testing.expect(std.meta.stringToEnum(identity.Kind, "feature_activation") == null);
    try std.testing.expect(@FieldType(ledger.Transition, "expected_ledger") == *const ledger.Ledger);
    try std.testing.expect(@FieldType(ledger.Candidate, "reservations") == []const ledger.Record);
    try std.testing.expect(ledger.Revision != model_request_identity.LedgerRevision);
    inline for (.{ @embedFile("domain/transaction_identity.zig"), @embedFile("domain/transaction_id_ledger.zig") }) |source| {
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/actions/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "NodeContract");
    }
}

test "transaction ledger stored format reuses domain authority and its documented sample round trips" {
    const codec = @import("adapters/parsers/transaction_id_ledger.zig");
    const identity = @import("domain/transaction_identity.zig");
    const ledger = @import("domain/transaction_id_ledger.zig");
    const source = @embedFile("adapters/parsers/transaction_id_ledger.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "ledger.createValidated") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "limits.ledger.validateCounts") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "json.validateTransport") != null);
    try expectAbsent(source, "utf8ValidateSlice");
    try expectAbsent(source, "NodeContract");
    try expectAbsent(source, "/actions/");
    try expectAbsent(source, "std.Io.Dir");
    try expectAbsent(source, "std.Io.File");
    try expectAbsent(@embedFile("domain/transaction_id_ledger.zig"), "std.json");

    const allocator = std.testing.allocator;
    const documented = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/transaction-id-ledger-format.md", allocator, .limited(65536));
    defer allocator.free(documented);
    const start = (std.mem.indexOf(u8, documented, "```json\n") orelse return error.MissingStoredFormatExample) + "```json\n".len;
    const end = std.mem.indexOf(u8, documented[start..], "```") orelse return error.MissingStoredFormatExample;
    const sample = documented[start..][0..end];
    const owner: identity.StorageOwner = .{
        .feature_id = .{ .bytes = "sample-feature" },
        .workflow_artifact_registry_state_id = .{
            .feature_id = .{ .bytes = "sample-feature" },
            .ordinal = 1,
        },
    };
    const parsed = try codec.decode(allocator, sample, owner, null, .{
        .maximum_bytes = 65536,
        .ledger = .{ .maximum_records = 10, .maximum_owner_bytes = 4096 },
    });
    defer ledger.deinitOwner(parsed);
    const bytes = try codec.encode(allocator, ledger.ledger(parsed), owner, 65536);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings(sample, bytes);
}

test "result schema authority is opaque and compilation remains a kernel concern" {
    const schema = @import("domain/model_result_schema.zig");
    try std.testing.expect(@typeInfo(schema.Schema) == .@"opaque");
    const resource = @import("domain/workflow_compilation.zig").CompiledResource;
    const content = @typeInfo(@FieldType(resource, "content")).@"union";
    try std.testing.expect(content.tag_type.? == @import("domain/workflow_operation.zig").ResourceKind);
    try std.testing.expect(@FieldType(@FieldType(resource, "content"), "result_schema") == *const schema.Schema);
    try std.testing.expect(@FieldType(llm_provider_operation.IdentifiedProviderNeutralModelRequest, "response_schema") == *const schema.Schema);
    const compiler = @embedFile("actions/workflow/compile_workflow_graphs.zig");
    try std.testing.expect(std.mem.indexOf(u8, compiler, "result_schema_compiler.compile") != null);
    try expectAbsent(compiler, "std.json");
    try expectAbsent(compiler, "/adapters/");
    const schema_domain = @embedFile("domain/model_result_schema.zig");
    try expectAbsent(schema_domain, "parseFromSlice");
    try expectAbsent(schema_domain, "std.Io");
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try expectAbsent(runner, "model_result_schema_compiler");
    try expectAbsent(runner, "parseFromSlice");
}

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
        try expectSingleActionContract(source);
    }
}

test "every orchestrator and coordinator is capability free" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var application = try std.Io.Dir.cwd().openDir(io, "src/application", .{ .iterate = true });
    defer application.close(io);

    var iterator = application.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or
            (!std.mem.endsWith(u8, entry.name, "_orchestrator.zig") and
                !std.mem.endsWith(u8, entry.name, "_coordinator.zig")))
        {
            continue;
        }
        const source = try application.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        try expectAbsent(source, "/actions/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "std.Io");
    }
}

test "every application runner is infrastructure independent" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var application = try std.Io.Dir.cwd().openDir(io, "src/application", .{ .iterate = true });
    defer application.close(io);

    var iterator = application.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, "_runner.zig")) continue;
        const source = try application.readFileAlloc(io, entry.name, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
    }
}

test "domain and port dependency direction is enforced repository wide" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    inline for (.{ "src/domain", "src/ports" }) |directory_path| {
        var directory = try std.Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true });
        defer directory.close(io);
        var walker = try directory.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
            defer allocator.free(source);
            try expectAbsent(source, "/actions/");
            try expectAbsent(source, "/application/");
            try expectAbsent(source, "/adapters/");
            try expectAbsent(source, "../actions/");
            try expectAbsent(source, "../application/");
            try expectAbsent(source, "../adapters/");
        }
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
    switch (@typeInfo(bootstrap_root_registry.LLMProviderConfigCapability)) {
        .@"opaque" => {},
        else => return error.ProviderConfigCapabilityMustBeOpaque,
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

    const provider_service = @embedFile("application/llm_provider_config_service.zig");
    try expectAbsent(provider_service, "std.Io");
    try expectAbsent(provider_service, "std.json");
    const root_domain = @embedFile("domain/bootstrap_root_registry.zig");
    const provider_adapter = @embedFile("adapters/filesystem/llm_provider_config_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, root_domain, "bindLLMProviderConfigSource") != null);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        provider_adapter,
        "bindLLMProviderConfigSource",
    ));
}

test "configuration domain ownership is independent of the JSON parser" {
    const source = @embedFile("domain/config.zig");
    try expectAbsent(source, "std.json.Parsed");
    try expectAbsent(source, "PublicError");
    try expectAbsent(source, "Registry");
}

test "provider config orchestration is capability free and runner owned" {
    const orchestrator = @embedFile("application/llm_provider_config_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    try expectAbsent(orchestrator, "std.Io");

    const runner = @embedFile("application/llm_provider_config_runner.zig");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "std.Io");
    try std.testing.expect(std.mem.indexOf(u8, runner, "envelope.apply") != null);

    const composition = @embedFile("composition/model_provider_bootstrap.zig");
    try std.testing.expect(std.mem.indexOf(u8, composition, "llm_provider_config_source.Adapter.init") != null);
    try std.testing.expect(std.mem.indexOf(u8, composition, "llm_provider_config_runner.Runner.init") != null);
}

test "conditional provider bootstrap has one orchestration and capture authority" {
    const orchestrator = @embedFile("application/model_provider_bootstrap_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    try expectAbsent(orchestrator, "std.Io");

    const runner = @embedFile("application/model_provider_bootstrap_runner.zig");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "/ports/");
    try expectAbsent(runner, "std.Io");
    try expectAbsent(runner, "locate_llm_provider_config.zig");
    try expectAbsent(runner, "read_llm_provider_config.zig");
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(runner, "config_orchestrator.run("),
    );
    try std.testing.expect(std.mem.indexOf(u8, runner, "envelope.apply") != null);

    const services = @embedFile("application/model_provider_bootstrap_services.zig");
    try expectAbsent(services, "std.json");
    try expectAbsent(services, "llm_provider_document");
    try expectAbsent(services, "config.zig");

    const binding = @embedFile("application/model_provider_bootstrap_binding.zig");
    try expectAbsent(binding, "/adapters/");
    try expectAbsent(binding, "std.Io");

    const assembly = @embedFile("composition/model_provider_bootstrap.zig");
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(assembly, "llm_provider_config_source.Adapter.init("),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(assembly, "orchestrator.run("),
    );

    const workflow_engine = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(workflow_engine, "/adapters/");
    try expectAbsent(workflow_engine, "std.Io");
    const select_index = std.mem.indexOf(u8, workflow_engine, "invokeSelectWorkflow()") orelse {
        return error.MissingWorkflowSelection;
    };
    const prepare_index = std.mem.indexOf(u8, workflow_engine, "invokePrepareWorkflow()") orelse {
        return error.MissingProviderBootstrapInvocation;
    };
    const execute_index = std.mem.indexOf(u8, workflow_engine, "invokeInvocation()") orelse {
        return error.MissingWorkflowExecution;
    };
    try std.testing.expect(select_index < prepare_index);
    try std.testing.expect(prepare_index < execute_index);

    const root = @embedFile("composition/root.zig");
    try expectAbsent(root, "loadLLMProviderConfigInProject");
    try expectAbsent(root, "llm_provider_config_orchestrator.zig");
}

test "provider catalogue and repository allowlist have one immutable authority each" {
    switch (@typeInfo(llm_provider_registry.ValidatedLLMProviderRegistry)) {
        .@"opaque" => {},
        else => return error.LLMProviderRegistryMustBeOpaque,
    }
    switch (@typeInfo(repository_model_allowlist.ValidatedRepositoryModelAllowlist)) {
        .@"opaque" => {},
        else => return error.RepositoryModelAllowlistMustBeOpaque,
    }

    const service = @embedFile("application/llm_provider_registry_service.zig");
    try expectAbsent(service, "std.json");
    try expectAbsent(service, "llm_provider_document");
    try expectAbsent(service, "config.zig");
    const init_type = @typeInfo(@TypeOf(
        llm_provider_registry_service.LLMProviderRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);
    try std.testing.expect(init_type.params[0].type.? == *llm_provider_registry.Owner);

    const registry = @embedFile("domain/llm_provider_registry.zig");
    try expectAbsent(registry, "/adapters/");
    try expectAbsent(registry, "/ports/");
    try expectAbsent(registry, "anyopaque");

    const allowlist_fields = @typeInfo(repository_model_allowlist.Entry).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 3), allowlist_fields.len);
    try std.testing.expectEqualStrings("slot_id", allowlist_fields[0].name);
    try std.testing.expect(allowlist_fields[0].type == @import("domain/llm_provider_identity.zig").ModelSlotId);
    try std.testing.expectEqualStrings("registry_entry_id", allowlist_fields[1].name);
    try std.testing.expectEqualStrings("reasoning_effort", allowlist_fields[2].name);
    try std.testing.expect(allowlist_fields[1].type == llm_provider_registry.RegistryEntryId);

    const allowlist = @embedFile("domain/repository_model_allowlist.zig");
    try expectAbsent(allowlist, "ValidatedProviderConfig");
    try expectAbsent(allowlist, "ProviderModelContract");
    try expectAbsent(allowlist, "/adapters/");
    try expectAbsent(allowlist, "/ports/");
}

test "model capability facts and effective limits have no configuration or operational authority" {
    const contracts = @import("domain/llm_provider_contracts.zig");
    const limits = @import("domain/model_limits.zig");
    const operation_contract = @import("domain/workflow_operation.zig");
    const provider_operation = @import("domain/llm_provider_operation.zig");
    try std.testing.expect(@FieldType(contracts.ProviderModelContract, "capabilities") == @import("domain/model_capabilities.zig").Capabilities);
    try std.testing.expect(@FieldType(provider_operation.IdentifiedProviderNeutralModelRequest, "limits") == limits.Limits);
    try std.testing.expect(!@hasDecl(provider_operation, "EffectiveModelLimits"));
    try std.testing.expect(!@hasField(operation_contract.PolicyProfile, "model_capacity"));
    try std.testing.expect(!@hasField(@import("domain/config.zig").ModelsConfig, "model_capacity"));
    inline for (.{
        @embedFile("domain/model_capabilities.zig"),
        @embedFile("domain/model_limits.zig"),
        @embedFile("domain/workflow_model.zig"),
        @embedFile("actions/provider/resolve_provider_model_binding.zig"),
    }) |source| {
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "std.process");
    }
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("actions/workflow/compile_workflow_graphs.zig"), "self.registry.model_capacity") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("application/workflow_pipeline_runner.zig"), "step.model orelse") != null);
}

test "request preparation is pure and reuses the sole request validation boundary" {
    const build_request = @import("actions/model/build_model_request.zig").Action;
    const validate_request = @import("actions/model/validate_static_model_request_capacity.zig").Action;
    inline for (.{ build_request, validate_request }) |Action| {
        try std.testing.expectEqual(@as(usize, 0), @typeInfo(Action).@"struct".fields.len);
        try std.testing.expect(Action.contract.side_effect == .none);
        try std.testing.expect(Action.contract.runner_accounting == .none);
    }
    const preparation = @import("domain/model_request_preparation.zig");
    try std.testing.expect(@FieldType(preparation.Owned, "request") == *const llm_provider_operation.IdentifiedProviderNeutralModelRequest);
    switch (@typeInfo(preparation.StaticCapacityEvidence)) {
        .@"opaque" => {},
        else => return error.ModelRequestCapacityEvidenceMustBeOpaque,
    }
    inline for (.{
        @embedFile("actions/model/build_model_request.zig"),
        @embedFile("actions/model/validate_static_model_request_capacity.zig"),
        @embedFile("domain/model_request_preparation.zig"),
    }) |source| {
        try expectAbsent(source, "/actions/");
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.process");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "countInputTokens");
    }
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("actions/model/build_model_request.zig"), "IdentifiedProviderNeutralModelRequest.init") != null);
    const validator = @embedFile("domain/model_request_preparation.zig");
    try std.testing.expect(std.mem.indexOf(u8, validator, "request.validate()") != null);
    try std.testing.expect(std.mem.indexOf(u8, validator, "request.matchesBinding(") != null);
}

test "provider observation validation exposes sealed candidate evidence without execution capabilities" {
    const validator = @import("actions/model/validate_provider_invocation_observation.zig").Action;
    const validated = @import("domain/provider_invocation_validation.zig");
    try std.testing.expectEqual(@as(usize, 0), @typeInfo(validator).@"struct".fields.len);
    try std.testing.expect(validator.contract.side_effect == .none);
    try std.testing.expect(validator.contract.runner_accounting == .none);
    inline for (.{ validated.Evidence, validated.CompleteCandidate }) |T| {
        switch (@typeInfo(T)) {
            .@"opaque" => {},
            else => return error.ProviderObservationEvidenceMustBeOpaque,
        }
    }
    try std.testing.expect(@FieldType(validated.Result, "complete") == *const validated.CompleteCandidate);
    try std.testing.expect(!@hasDecl(validated.Evidence, "content"));
    try std.testing.expect(!@hasField(validated.Result, "invalid"));
    try std.testing.expect(!@hasField(validated.Result, "cancelled"));
    inline for (.{
        @embedFile("actions/model/validate_provider_invocation_observation.zig"),
        @embedFile("domain/provider_invocation_validation.zig"),
    }) |source| {
        try expectAbsent(source, "/actions/");
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.process");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "std.json");
        try expectAbsent(source, "countInputTokens");
        try expectAbsent(source, "workflow_token_accounting");
        try expectAbsent(source, "logger");
    }
    const source = @embedFile("domain/provider_invocation_validation.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "requireInvoked(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "validateInferenceInvocation(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "ProviderUsage.init(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "CompleteBoundedOwnedUtf8.validate(") != null);
}

test "model decoding consumes sealed complete evidence and exposes only immutable JSON views" {
    const decoder = @import("actions/model/decode_model_envelope.zig").Action;
    const decoded = @import("domain/model_envelope.zig");
    const validated = @import("domain/provider_invocation_validation.zig");
    try std.testing.expectEqual(@as(usize, 0), @typeInfo(decoder).@"struct".fields.len);
    try std.testing.expect(decoder.contract.side_effect == .none);
    try std.testing.expect(decoder.contract.runner_accounting == .none);
    const execute = @typeInfo(@TypeOf(decoder.execute)).@"fn";
    try std.testing.expectEqual(@as(usize, 3), execute.params.len);
    try std.testing.expect(execute.params[2].type.? == *const validated.CompleteCandidate);
    inline for (.{ decoded.Candidate, decoded.Object, decoded.Array }) |T| {
        switch (@typeInfo(T)) {
            .@"opaque" => {},
            else => return error.DecodedModelViewsMustBeOpaque,
        }
    }
    try std.testing.expect(@FieldType(decoded.Owned, "candidate") == *const decoded.Candidate);
    try std.testing.expect(@FieldType(decoded.Value, "object") == *const decoded.Object);
    try std.testing.expect(@FieldType(decoded.Value, "array") == *const decoded.Array);
    try std.testing.expect(@FieldType(decoded.Value, "string") == []const u8);
    try std.testing.expect(@FieldType(decoded.Value, "number") == []const u8);
    inline for (.{
        @embedFile("actions/model/decode_model_envelope.zig"),
        @embedFile("domain/model_envelope.zig"),
        @embedFile("domain/strict_json.zig"),
    }) |source| {
        inline for (.{ "/actions/", "/ports/", "/adapters/", "anyopaque", "@constCast", "std.Io", "std.http", "std.process", "workflow_token_accounting", "logger", "validateInferenceInvocation", "requireInvoked", "schema.compile" }) |forbidden| {
            try expectAbsent(source, forbidden);
        }
    }
    // Schema transport and model-result transport reuse the syntax boundary;
    // only their distinct owners choose root shape, schema and number policy.
    inline for (.{ @embedFile("domain/model_envelope.zig"), @embedFile("adapters/parsers/model_result_schemas.zig") }) |source| {
        try std.testing.expect(std.mem.indexOf(u8, source, "json.parse(") != null);
        try expectAbsent(source, "std.json.parseFromSlice");
        try expectAbsent(source, "Scanner.initCompleteInput");
    }
}

test "payload validation uses only the retained schema and produces allocation-free candidate evidence" {
    const validator = @import("actions/model/validate_model_payload_schema.zig").Action;
    const validation = @import("domain/model_payload_schema.zig");
    const envelope = @import("domain/model_envelope.zig");
    try std.testing.expectEqual(@as(usize, 0), @typeInfo(validator).@"struct".fields.len);
    try std.testing.expect(validator.contract.side_effect == .none);
    try std.testing.expect(validator.contract.runner_accounting == .none);
    const execute = @typeInfo(@TypeOf(validator.execute)).@"fn";
    try std.testing.expectEqual(@as(usize, 2), execute.params.len);
    try std.testing.expect(execute.params[1].type.? == *const envelope.Candidate);
    try std.testing.expect(execute.return_type.? == validation.Result);
    try std.testing.expect(@FieldType(validation.Result, "valid") == *const validation.Evidence);
    try std.testing.expect(@FieldType(validation.Result, "invalid") == validation.Rejection);
    try std.testing.expectEqual(@as(usize, 2), @typeInfo(validation.Result).@"union".fields.len);
    switch (@typeInfo(validation.Evidence)) {
        .@"opaque" => {},
        else => return error.PayloadSchemaEvidenceMustBeOpaque,
    }
    try std.testing.expect(@typeInfo(@TypeOf(validation.Evidence.candidate)).@"fn".return_type.? == *const envelope.Candidate);
    inline for (.{ @embedFile("actions/model/validate_model_payload_schema.zig"), @embedFile("domain/model_payload_schema.zig") }) |source| {
        inline for (.{ "/actions/", "/ports/", "/adapters/", "anyopaque", "@constCast", "std.Io", "std.http", "std.process", "std.json", "parseFloat", "Allocator", "workflow_token_accounting", "logger", "validateInferenceInvocation", "requireInvoked", "schema.compile" }) |forbidden| {
            try expectAbsent(source, forbidden);
        }
    }
    const source = @embedFile("domain/model_payload_schema.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "candidate.association().request().response_schema") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "schema.findProperty(") != null);
}

test "model-binding requirement is immutable data not a provider-call capability" {
    const compilation = @import("domain/workflow_compilation.zig");
    const operation = @import("domain/workflow_operation.zig");
    const registry = @import("ports/workflow_operation_registry.zig");
    try std.testing.expect(@FieldType(compilation.CompiledStep, "model") == ?@import("domain/workflow_model.zig").Requirements);
    try std.testing.expect(@FieldType(operation.Contract, "model_capacity") == ?@import("domain/model_limits.zig").Capacity);
    try std.testing.expect(@FieldType(registry.StepInput, "model_binding") == ?*const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding);
    try std.testing.expect(!@hasField(registry.StepInput, "provider"));
    const derive = @embedFile("actions/provider/derive_provider_requirement.zig");
    try std.testing.expect(std.mem.indexOf(u8, derive, "step.model != null") != null);
    try expectAbsent(derive, "step.parameters");
    try expectAbsent(@embedFile("actions/provider/resolve_provider_model_binding.zig"), "LLMProviderInterface");
}

test "model request identity has one opaque ledger and runner applied mutation boundary" {
    switch (@typeInfo(model_request_identity.ModelRequestIdentityLedger)) {
        .@"opaque" => {},
        else => return error.ModelRequestIdentityLedgerMustBeOpaque,
    }
    switch (@typeInfo(model_request_identity.ModelRequestBindingEvidence)) {
        .@"opaque" => {},
        else => return error.ModelRequestBindingEvidenceMustBeOpaque,
    }

    const builder = @embedFile("actions/model/build_initial_model_request_identity_ledger.zig");
    const assigner = @embedFile("actions/model/assign_model_request_id.zig");
    const lifecycle = @embedFile("actions/model/advance_model_request_lifecycle.zig");
    const validator = @embedFile("actions/model/validate_model_request_binding.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        builder,
        ".produces = &.{.model_request_identity_ledger}",
    ));
    try expectAbsent(builder, ".replaces = &.{.model_request_identity_ledger}");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        assigner,
        ".replaces = &.{.model_request_identity_ledger}",
    ));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        lifecycle,
        ".replaces = &.{.model_request_identity_ledger}",
    ));
    try expectAbsent(lifecycle, "/ports/");
    try expectAbsent(lifecycle, "/adapters/");
    try expectAbsent(validator, ".produces = &.{.model_request_identity_ledger}");
    try expectAbsent(validator, ".replaces = &.{.model_request_identity_ledger}");

    const runner = @embedFile("application/model_request_identity_runner.zig");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "/ports/");
    try expectAbsent(runner, "std.Io");
    try std.testing.expectEqual(@as(usize, 3), countOccurrences(runner, "envelope.apply("));
}

test "model invocation forwards one call through the sole provider port without hidden work" {
    const action = @import("actions/model/invoke_model.zig").Action;
    try std.testing.expectEqual(@as(usize, 1), @typeInfo(action).@"struct".fields.len);
    try std.testing.expect(@FieldType(action, "provider") == llm_provider_interface.LLMProviderInterface);
    try std.testing.expect(action.contract.side_effect == .model_call);
    try std.testing.expect(action.contract.runner_accounting == .none);
    const signature = @typeInfo(@TypeOf(action.execute)).@"fn";
    try std.testing.expectEqual(@as(usize, 5), signature.params.len);
    try std.testing.expect(signature.params[1].type.? == *const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding);
    try std.testing.expect(signature.params[2].type.? == *const llm_provider_operation.IdentifiedProviderNeutralModelRequest);
    try std.testing.expect(signature.params[3].type.? == *const llm_provider_operation.ValidatedProviderAuthorizationLeaseRef);
    try std.testing.expect(signature.params[4].type.? == *const llm_provider_operation.InvokedProviderOperation);
    try std.testing.expect(signature.return_type.? == llm_provider_interface.Error!llm_provider_operation.ProviderInvocationObservation);
    const capabilities = comptime @import("application/workflow_operation_binding.zig").inspect(action, &.{});
    try std.testing.expect(capabilities.valid and capabilities.model_provider);
    try std.testing.expect(!capabilities.toolchain_read and !capabilities.toolchain_parser and !capabilities.reference_read);
    const source = @embedFile("actions/model/invoke_model.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.provider.invoke("));
    inline for (.{ "/actions/", "/application/", "/adapters/", "anyopaque", "@constCast", "std.Io", "std.http", "std.process", "std.json", "countInputTokens", "while (", "for (", "catch", ".deinit(", "validateInferenceInvocation", "requireInvoked", "schema", "workflow_token_accounting", "logger" }) |forbidden| {
        try expectAbsent(source, forbidden);
    }
    // This increment provides an action, not a production provider activation.
    try expectAbsent(@embedFile("composition/native_workflow_operations.zig"), "invoke_model.zig");
}

test "provider operation boundary has one capability-limited interface" {
    switch (@typeInfo(llm_provider_interface.Context)) {
        .@"opaque" => {},
        else => return error.LLMProviderContextMustBeOpaque,
    }
    try std.testing.expectEqual(
        @as(usize, 2),
        @typeInfo(llm_provider_interface.LLMProviderInterface.VTable).@"struct".fields.len,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        std.enums.values(llm_provider_operation.ProviderFailureCause).len,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        std.enums.values(llm_provider_operation.ProviderDeliveryDisposition).len,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        std.enums.values(llm_provider_operation.ProviderRetryClass).len,
    );

    const port = @embedFile("ports/llm_provider_interface.zig");
    try expectAbsent(port, "anyopaque");
    try expectAbsent(port, "/adapters/");
    try expectAbsent(port, "std.Io");
    try expectAbsent(port, "ExactInputTokenCountEvidence");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(port, "pub const LLMProviderInterface"));

    const contract = @embedFile("domain/llm_provider_operation.zig");
    try expectAbsent(contract, "/adapters/");
    try expectAbsent(contract, "/ports/");
    try expectAbsent(contract, "std.Io");

    const fake = @embedFile("adapters/provider/fake_llm_provider.zig");
    try expectAbsent(fake, "std.Io");
    try expectAbsent(fake, "filesystem");
    try expectAbsent(fake, "process");
    try expectAbsent(fake, "environment");
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "fake_llm_provider");
}

test "provider authorization exposes only non-operational references and narrow single-use ports" {
    const preparation = @import("ports/provider_operation_authorization.zig");
    const lease = @import("ports/provider_authorization_lease.zig");
    const reference = @import("domain/execution_reference.zig");
    const ref_fields = @typeInfo(llm_provider_operation.ValidatedProviderAuthorizationLeaseRef).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 1), ref_fields.len);
    try std.testing.expect(ref_fields[0].type == reference.Ref);
    try std.testing.expect(!@hasDecl(llm_provider_operation.ValidatedProviderAuthorizationLeaseRef, "init"));
    try std.testing.expect(!@hasDecl(llm_provider_operation.ValidatedProviderAuthorizationLeaseRef, "matches"));
    try std.testing.expect(!@hasField(preparation.Slot, "publish_fn"));
    try std.testing.expect(!@hasField(preparation.Slot, "consume_fn"));
    try std.testing.expect(@hasField(preparation.AllocatedSlot, "publish_fn"));
    try std.testing.expect(!@hasField(lease.Port, "deposit_fn"));

    inline for (.{
        "ports/provider_operation_authorization.zig",
        "ports/provider_authorization_lease.zig",
        "actions/model/prepare_provider_operation_authorization.zig",
        "application/provider_authorization_lease_table.zig",
        "application/provider_authorization_runner.zig",
        "adapters/provider/fake_provider_authorization.zig",
    }) |path| {
        const source = @embedFile(path);
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "std.process");
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "@constCast");
    }
    const fake = @embedFile("adapters/provider/fake_llm_provider.zig");
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(fake, "authorization_leases.consume("));
    try expectAbsent(fake, "/application/");
    const preloader = @embedFile("adapters/provider/fake_provider_authorization.zig");
    try expectAbsent(preloader, "/application/");
    try expectAbsent(preloader, "getEnv");
    const runner = @embedFile("application/provider_operation_lifecycle_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "authorization_leases.deinit()").? < std.mem.indexOf(u8, runner, "lifecycle.deinitOwner(").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "self.ledger = try lifecycle.apply(").? < std.mem.indexOf(u8, runner, "authorization_leases.update(").?);
    const prepare_action = @embedFile("actions/model/prepare_provider_operation_authorization.zig");
    try expectAbsent(prepare_action, "llm_provider_interface");
    try expectAbsent(prepare_action, "lifecycle.apply");
    try std.testing.expect(std.mem.indexOf(u8, prepare_action, "delta.data_writes[") != null);
}

test "model attempt accounting has one runner-applied transition authority" {
    switch (@typeInfo(model_attempt_accounting.RunnerModelAttemptAccounting)) {
        .@"opaque" => {},
        else => return error.RunnerModelAttemptAccountingMustBeOpaque,
    }

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        const declarations = countOccurrences(source, ".runner_accounting = .increment_model_attempt");
        if (std.mem.eql(u8, entry.path, "model/advance_model_attempt_accounting.zig")) {
            try std.testing.expectEqual(@as(usize, 1), declarations);
        } else {
            try std.testing.expectEqual(@as(usize, 0), declarations);
        }
    }

    const action = @embedFile("actions/model/advance_model_attempt_accounting.zig");
    try expectAbsent(action, "/ports/");
    try expectAbsent(action, "/adapters/");
    try expectAbsent(action, "std.Io");
    const accounting = @embedFile("domain/model_attempt_accounting.zig");
    try expectAbsent(accounting, "/ports/");
    try expectAbsent(accounting, "/adapters/");
    try expectAbsent(accounting, "std.Io");
    try expectAbsent(accounting, "MaximumAttempts");
    try expectAbsent(accounting, "configured");
    try expectAbsent(accounting, "hard");

    const request_identity = @embedFile("domain/model_request_identity.zig");
    try expectAbsent(request_identity, "not_invoked_attempt_ceiling");

    const workflow_operation = @embedFile("domain/workflow_operation.zig");
    try expectAbsent(workflow_operation, "loop_budget");
    try expectAbsent(workflow_operation, "retry_count");

    const runner = @embedFile("application/model_attempt_accounting_runner.zig");
    try expectAbsent(runner, "/ports/");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "std.Io");
    const validate_index = std.mem.indexOf(u8, runner, "envelope.applyDelta(").?;
    const apply_index = std.mem.indexOf(u8, runner, "accounting.apply(").?;
    const replace_index = std.mem.indexOf(u8, runner, "self.current_owner = successor").?;
    try std.testing.expect(validate_index < apply_index);
    try std.testing.expect(apply_index < replace_index);
}

test "workflow token accounting has one mutation authority and a read-only check" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        const reconciles = countOccurrences(source, ".runner_accounting = .reconcile_workflow_tokens");
        try std.testing.expectEqual(
            @as(usize, if (std.mem.eql(u8, entry.path, "model/reconcile_workflow_token_usage.zig")) 1 else 0),
            reconciles,
        );
    }

    inline for (.{
        "actions/model/check_workflow_token_budget.zig",
        "actions/model/reconcile_workflow_token_usage.zig",
    }) |path| {
        const source = @embedFile(path);
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
    }
    const tokens = @import("domain/workflow_token_accounting.zig");
    try std.testing.expect(!@hasDecl(tokens, "ReservationTransition"));
    try std.testing.expect(!@hasField(tokens.Ledger, "reserved_tokens"));
    try std.testing.expect(@import("actions/model/check_workflow_token_budget.zig").Action.contract.runner_accounting == .none);
}

test "provider lifecycle has one pure action and runner-owned immutable ledger" {
    const lifecycle = @import("domain/provider_operation_lifecycle.zig");
    try std.testing.expect(@FieldType(lifecycle.Command, "assign_count") == lifecycle.Assignment);
    try std.testing.expect(@FieldType(lifecycle.Command, "assign_inference") == lifecycle.Assignment);
    switch (@typeInfo(lifecycle.Ledger)) {
        .@"opaque" => {},
        else => return error.ProviderOperationLedgerMustBeOpaque,
    }
    try std.testing.expect(@TypeOf(@as(lifecycle.TerminalSummary, .counted).counted) == void);
    try std.testing.expect(!@hasField(lifecycle.Effect, "content"));

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        try std.testing.expectEqual(
            @as(usize, if (std.mem.eql(u8, entry.path, "model/advance_provider_operation_lifecycle.zig")) 1 else 0),
            countOccurrences(source, ".runner_accounting = .advance_provider_operation"),
        );
    }
    inline for (.{
        "actions/model/advance_provider_operation_lifecycle.zig",
        "domain/provider_operation_lifecycle.zig",
        "application/provider_operation_lifecycle_runner.zig",
    }) |path| {
        const source = @embedFile(path);
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
    }
    const action_source = @embedFile("actions/model/advance_provider_operation_lifecycle.zig");
    try expectAbsent(action_source, "lifecycle.apply(");
    const runner = @embedFile("application/provider_operation_lifecycle_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "envelope.applyDelta(").? < std.mem.indexOf(u8, runner, "lifecycle.apply(").?);
    const request_runner = @embedFile("application/model_request_identity_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, request_runner, "operations.deinit()").? < std.mem.indexOf(u8, request_runner, "identity.deinitOwner(owner)").?);
}

test "only request identity owners can produce or replace its ledger key" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(
            io,
            entry.basename,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        const produces = countOccurrences(source, ".produces = &.{.model_request_identity_ledger}");
        const replaces = countOccurrences(source, ".replaces = &.{.model_request_identity_ledger}");
        if (std.mem.eql(u8, entry.path, "model/build_initial_model_request_identity_ledger.zig")) {
            try std.testing.expectEqual(@as(usize, 1), produces);
        } else {
            try std.testing.expectEqual(@as(usize, 0), produces);
        }
        if (std.mem.eql(u8, entry.path, "model/assign_model_request_id.zig") or
            std.mem.eql(u8, entry.path, "model/advance_model_request_lifecycle.zig"))
        {
            try std.testing.expectEqual(@as(usize, 1), replaces);
        } else {
            try std.testing.expectEqual(@as(usize, 0), replaces);
        }
    }
}

test "provider requirement derives only from one exactly selected compiled workflow" {
    const action_source = @embedFile("actions/provider/derive_provider_requirement.zig");
    try expectAbsent(action_source, "/adapters/");
    try expectAbsent(action_source, "/ports/");
    try expectAbsent(action_source, "std.Io");
    try expectAbsent(action_source, "config.zig");
    try expectAbsent(action_source, "sddproviders");
    try expectAbsent(action_source, "\"specify\"");
    try expectAbsent(action_source, "\"implement\"");

    const execute_type = @typeInfo(@TypeOf(derive_provider_requirement.Action.execute)).@"fn";
    try std.testing.expectEqual(@as(usize, 2), execute_type.params.len);
    try std.testing.expect(execute_type.params[1].type.? == *const workflow_execution.SelectedWorkflow);
    try std.testing.expectEqualSlices(
        @import("domain/pipeline.zig").DataKey,
        &.{.selected_compiled_workflow},
        derive_provider_requirement.Action.contract.requires,
    );
    try std.testing.expectEqualSlices(
        @import("domain/pipeline.zig").DataKey,
        &.{.model_provider_requirement},
        derive_provider_requirement.Action.contract.produces,
    );
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
    try std.testing.expect(std.mem.indexOf(u8, compiler, "resolveOperation") != null);
    try expectAbsent(compiler, "spec.section.generate");
    try expectAbsent(compiler, "implementation.operation.generate");

    const operation_port = @embedFile("ports/workflow_operation_registry.zig");
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "operations: []const Entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "contract.kind == .invocation") != null);
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "contract.kind != .step") != null);
    try expectAbsent(operation_port, "CompilerRegistry");
    try expectAbsent(operation_port, "NodeImplementation");

    const operation_bindings = @embedFile("composition/core_workflow_operations.zig");
    try expectAbsent(operation_bindings, "specify");
    try expectAbsent(operation_bindings, "plan");
    try expectAbsent(operation_bindings, "tasks");
    try expectAbsent(operation_bindings, "implement");

    const workflow_runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(workflow_runner, "resolveOperation"));
    try expectAbsent(workflow_runner, "resolveInvocation");
    try expectAbsent(workflow_runner, "resolveNode");
    try expectAbsent(workflow_runner, "workflow_node_implementation");

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
    try expectAbsent(workflow_domain, "validInventoryPath");
    try expectAbsent(workflow_domain, "classifyInventoryDescriptor");
    try expectAbsent(workflow_domain, "RawNode");
    try expectAbsent(workflow_domain, "CompilerRegistry");

    const vocabulary = @embedFile("domain/workflow.zig");
    try expectAbsent(vocabulary, "InventoryDescriptor");
    try expectAbsent(vocabulary, "RawDefinition");
    try expectAbsent(vocabulary, "CompiledWorkflow");
    try expectAbsent(vocabulary, "ValidatedWorkflowDefinitionRegistry");

    const inventory_domain = @embedFile("domain/workflow_inventory.zig");
    try expectAbsent(inventory_domain, "RawDefinition");
    try expectAbsent(inventory_domain, "CompilerRegistry");
    try expectAbsent(inventory_domain, "CompiledWorkflow");

    const definition_domain = @embedFile("domain/workflow_definition.zig");
    try expectAbsent(definition_domain, "InventoryDescriptor");
    try expectAbsent(definition_domain, "CompilerRegistry");
    try expectAbsent(definition_domain, "ValidatedWorkflowDefinitionRegistry");

    const compilation_domain = @embedFile("domain/workflow_compilation.zig");
    try expectAbsent(compilation_domain, "InventoryDescriptor");
    try expectAbsent(compilation_domain, "RawDefinition");
    try expectAbsent(compilation_domain, "ValidatedWorkflowDefinitionRegistry");

    const capture = @embedFile("actions/workflow/capture_workflow_definitions.zig");
    const budget_index = std.mem.indexOf(u8, capture, "validateCaptureBudget") orelse return error.MissingWorkflowCaptureBudget;
    const read_index = std.mem.indexOf(u8, capture, "source.capture") orelse return error.MissingWorkflowCapture;
    try std.testing.expect(budget_index < read_index);
}

test "toolchain safety authority is opaque and path handoff has one adapter consumer" {
    switch (@typeInfo(toolchain_safety.ValidToolchain)) {
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

    const contracts = @embedFile("domain/toolchain.zig");
    try expectAbsent(contracts, "validateCaptureBudget(");
    try expectAbsent(contracts, "parseProject(");
    try expectAbsent(contracts, "parseRegistry(");
    try expectAbsent(contracts, "validateCompleteRegistry(");
    try expectAbsent(contracts, "pub fn resolve(");
    try expectAbsent(contracts, "pub fn compose(");
    try expectAbsent(contracts, "pub fn validate(");
    try expectAbsent(contracts, "pub const Owner");

    const accounting = @embedFile("domain/toolchain_accounting.zig");
    try expectAbsent(accounting, "parseProject(");
    try expectAbsent(accounting, "resolve(");
    try expectAbsent(accounting, "compose(");
    const schema = @embedFile("domain/toolchain_schema.zig");
    try expectAbsent(schema, "validateCaptureBudget(");
    try expectAbsent(schema, "validateCompleteRegistry(");
    try expectAbsent(schema, "compose(");
    const inheritance = @embedFile("domain/toolchain_inheritance.zig");
    try expectAbsent(inheritance, "parseProject(");
    try expectAbsent(inheritance, "compose(");
    const composition = @embedFile("domain/toolchain_composition.zig");
    try expectAbsent(composition, "parseProject(");
    try expectAbsent(composition, "resolve(");
    try expectAbsent(composition, "pub fn validate(");
    const safety = @embedFile("domain/toolchain_safety.zig");
    try expectAbsent(safety, "parseProject(");
    try expectAbsent(safety, "validateCompleteRegistry(");
    try expectAbsent(safety, "compose(");
}

test "bootstrap source ports and workflow inventory stages remain single purpose" {
    const workflow_ports = @embedFile("ports/workflow_authority_source.zig");
    try expectAbsent(workflow_ports, "pub const Source");
    try std.testing.expect(std.mem.indexOf(u8, workflow_ports, "pub const Enumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, workflow_ports, "pub const Capturer") != null);

    const toolchain_ports = @embedFile("ports/toolchain_authority_source.zig");
    try expectAbsent(toolchain_ports, "pub const Source");
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const ProjectCapturer") != null);
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const PresetEnumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const PresetCapturer") != null);

    const runner = @embedFile("application/bootstrap_runner.zig");
    try expectAbsent(runner, "inventory_workflow_authority.zig");
    const inventory_stages = [_][]const u8{
        @embedFile("actions/workflow/enumerate_workflow_authority_resources.zig"),
        @embedFile("actions/workflow/normalize_workflow_authority_entries.zig"),
        @embedFile("actions/workflow/build_workflow_authority_entry_accounts.zig"),
        @embedFile("actions/workflow/build_workflow_authority_inventory.zig"),
        @embedFile("actions/workflow/validate_workflow_authority_inventory.zig"),
    };
    for (inventory_stages) |source| {
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub fn execute("));
    }
}

test "bootstrap dispatcher delegates to focused runners" {
    const dispatcher = @embedFile("application/bootstrap_runner.zig");
    try expectAbsent(dispatcher, "/actions/");
    try expectAbsent(dispatcher, "/adapters/");
    try expectAbsent(dispatcher, "std.Io");

    const config_runner = @embedFile("application/bootstrap_config_runner.zig");
    try expectAbsent(config_runner, "/actions/bootstrap/");
    try expectAbsent(config_runner, "/actions/workflow/");
    try expectAbsent(config_runner, "/actions/toolchain/");

    const root_runner = @embedFile("application/bootstrap_root_runner.zig");
    try expectAbsent(root_runner, "/actions/config/");
    try expectAbsent(root_runner, "/actions/workflow/");
    try expectAbsent(root_runner, "/actions/toolchain/");

    const workflow_runner = @embedFile("application/bootstrap_workflow_runner.zig");
    try expectAbsent(workflow_runner, "/actions/config/");
    try expectAbsent(workflow_runner, "/actions/bootstrap/");
    try expectAbsent(workflow_runner, "/actions/toolchain/");

    const toolchain_runner = @embedFile("application/toolchain_workflow_runner.zig");
    try expectAbsent(toolchain_runner, "/actions/config/");
    try expectAbsent(toolchain_runner, "/actions/bootstrap/");
    try expectAbsent(toolchain_runner, "/actions/workflow/");
}

test "configured path policy and resolution have distinct action owners" {
    const runner = @embedFile("application/bootstrap_root_runner.zig");
    try expectAbsent(runner, "validate_engine_path_policy.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "validate_configured_root_path_policy.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, runner, "validate_llm_provider_config_path_policy.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, runner, "resolve_configured_base_root.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, runner, "resolve_llm_provider_config_path.zig") != null);

    const root_resolution = @embedFile("actions/bootstrap/resolve_configured_base_root.zig");
    try expectAbsent(root_resolution, "LLMProviderConfig");
    const provider_resolution = @embedFile("actions/bootstrap/resolve_llm_provider_config_path.zig");
    try expectAbsent(provider_resolution, "PathKey");
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
    const invocation_assembly = @embedFile("composition/engine_invocation.zig");
    try std.testing.expect(std.mem.indexOf(u8, invocation_assembly, "services.logs.barrier()") != null);
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "feature_log_lifecycle.Lifecycle");
    try expectAbsent(composition, "unbound_telemetry_barrier");
}

test "feature logging policy execution and filesystem operations have focused owners" {
    const port = @embedFile("ports/feature_log_sink.zig");
    try expectAbsent(port, "pub const Sink");
    try expectAbsent(port, "pub const VTable");

    const runner = @embedFile("application/feature_log_runner.zig");
    try expectAbsent(runner, "feature_log_sink.zig");
    try expectAbsent(runner, "trusted_log_clock.zig");
    try expectAbsent(runner, "console_log_sink.zig");
    try expectAbsent(runner, "emergency_log_sink.zig");
    try expectAbsent(runner, "transaction_stabilizer.zig");
    try expectAbsent(runner, "serialize_feature_log_record.zig");
    try expectAbsent(runner, "fn terminalEvent");
    try expectAbsent(runner, "fn promptSelected");
    try expectAbsent(runner, "fn updateState");
    try std.testing.expect(std.mem.indexOf(u8, runner, "feature_log_child_bindings.zig") != null);
    const orchestrator = @embedFile("application/feature_log_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try expectAbsent(orchestrator, "/adapters/");
    try expectAbsent(orchestrator, "/ports/");
    const transition = @embedFile("application/feature_log_policy_transition_coordinator.zig");
    try expectAbsent(transition, "feature_log_runner.zig");
    const finalization = @embedFile("application/feature_log_finalization_coordinator.zig");
    try expectAbsent(finalization, "feature_log_runner.zig");
    const retention = @embedFile("application/feature_log_retention_coordinator.zig");
    try expectAbsent(retention, "feature_log_runner.zig");

    const domain_modules = [_][]const u8{
        @embedFile("domain/feature_log_binding.zig"),
        @embedFile("domain/feature_log_stream.zig"),
        @embedFile("domain/feature_log_retention.zig"),
        @embedFile("domain/log_event_registry.zig"),
        @embedFile("domain/log_policy.zig"),
        @embedFile("domain/sanitized_prompt_log.zig"),
    };
    for (domain_modules) |source| {
        try expectAbsent(source, "BarrierOutcome");
    }

    const adapter = @embedFile("adapters/filesystem/feature_log_sink.zig");
    try expectAbsent(adapter, ".iterate(");
    try expectAbsent(adapter, ".openFile(");
    try expectAbsent(adapter, ".createFile(");
    try expectAbsent(adapter, "validateEncodedRow");
    try expectAbsent(adapter, "allocRemaining");
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_lock.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_recovery.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_retention_store.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_segment_store.zig") != null);

    const recovery = @embedFile("adapters/filesystem/feature_log_recovery.zig");
    try std.testing.expect(std.mem.indexOf(u8, recovery, "domain/feature_log_format.zig") != null);
    try expectAbsent(recovery, "fn cellAt");
    try expectAbsent(recovery, "fn parseUtc");
}

test "workflow engine owns selection while composition binds focused runners" {
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "parse_workflow_invocation.zig");
    try expectAbsent(composition, "select_compiled_workflow.zig");
    const orchestrator = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(orchestrator, "/actions/");
    try std.testing.expect(std.mem.indexOf(u8, orchestrator, "invokeParseInvocation()") != null);
    try std.testing.expect(std.mem.indexOf(u8, orchestrator, "invokeSelectWorkflow()") != null);
    const selection_runner = @embedFile("application/workflow_selection_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, selection_runner, "parse_workflow_invocation.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, selection_runner, "select_compiled_workflow.zig") != null);
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

test "workflow values have one runner-owned store and no key-only candidate API" {
    const pipeline = @import("domain/pipeline.zig");
    const data = @import("domain/pipeline_data.zig");
    try std.testing.expect(!@hasDecl(pipeline.NodeDelta, "successful"));
    try std.testing.expect(@FieldType(pipeline.NodeDelta, "data_writes") == data.Slots);
    try std.testing.expect(@FieldType(pipeline.NodeDelta, "data_replacements") == data.Slots);
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "self.envelope.view(") != null);
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(runner, "defer self.envelope.discard(&candidate.delta)"));
    const envelope = @embedFile("application/pipeline_envelope.zig");
    try expectAbsent(envelope, "@ptrCast");
    try expectAbsent(envelope, "/adapters/");
    try expectAbsent(@embedFile("domain/pipeline_data.zig"), "@ptrCast");
}

test "workflow operation capabilities have one typed binding authority" {
    const operations = @import("ports/workflow_operation_registry.zig");
    try std.testing.expect(!@hasField(@import("domain/workflow_operation.zig").Contract, "capabilities"));
    try std.testing.expect(!@hasField(operations.Registry, "capabilities"));
    try std.testing.expect(!@hasField(operations.Entry, "invoke_fn"));
    try std.testing.expect(!@hasField(operations.Entry, "context"));
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "application/workflow_operation_binding.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        try expectAbsent(source, ".implementation =");
    }
}

test "toolchain setup has no unconditional startup path or second result owner" {
    try std.testing.expect(!@hasField(@import("application/bootstrap_services.zig").BootstrapServices, "toolchain"));
    try expectAbsent(@embedFile("application/bootstrap_orchestrator.zig"), "Toolchain");
    try expectAbsent(@embedFile("application/bootstrap_runner.zig"), "toolchain");
    const service = @import("application/toolchain_service.zig").ToolChainService;
    try std.testing.expect(!@hasField(service, "owner"));
    try std.testing.expect(!@hasDecl(service, "deinit"));
    const bindings = @embedFile("application/toolchain_workflow_runner.zig");
    try expectAbsent(bindings, "successor");
    try expectAbsent(bindings, "bootstrap_root_registry");
    try std.testing.expect(std.mem.indexOf(u8, bindings, "values.adopt(") != null);
}

test "reference preflight shares path safety without leaking normalization or read capabilities" {
    const actions = @embedFile("application/reference_workflow_runner.zig");
    try expectAbsent(actions, "std.Io.Dir");
    try expectAbsent(actions, "/adapters/");
    try expectAbsent(actions, "bootstrap_root_registry");
    const selector = @embedFile("domain/reference_selector.zig");
    try expectAbsent(selector, "@cImport");
    try expectAbsent(selector, "/adapters/");
    try std.testing.expect(std.mem.indexOf(u8, selector, "path_policy.validateComponent") != null);
    try std.testing.expect(std.mem.indexOf(u8, selector, "path_policy.hasEncodedDotOrSeparator") != null);
    const filesystem = @embedFile("adapters/filesystem/reference_directory_inspector.zig");
    try std.testing.expect(std.mem.indexOf(u8, filesystem, "bindReferenceSourcesAdapter") != null);
    try std.testing.expect(std.mem.indexOf(u8, filesystem, "directories.open") != null);
    try expectAbsent(filesystem, "createDir");
    try expectAbsent(filesystem, "writeFile");
    const engine = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(engine, "specify");
    try expectAbsent(engine, "reference");
}

test "reference root path handoff has one authorized adapter consumer" {
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "domain/bootstrap_root_registry.zig") or
            std.mem.eql(u8, entry.path, "adapters/filesystem/reference_directory_inspector.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "bindReferenceSourcesAdapter");
    }
}

test "feature identity shares portable naming policy and has no operational authority" {
    const domain = @embedFile("domain/feature_identity.zig");
    try expectAbsent(domain, "@cImport");
    try expectAbsent(domain, "/adapters/");
    try std.testing.expect(std.mem.indexOf(u8, domain, "path_policy.validateComponent") != null);
    const action = @embedFile("actions/specify/derive_feature_identity.zig");
    try expectAbsent(action, "std.Io.Dir");
    try expectAbsent(action, "/adapters/");
    try expectAbsent(action, "model_provider");
    try std.testing.expect(std.mem.indexOf(u8, action, "normalizer.fold") != null);
    const runner = @embedFile("application/feature_identity_workflow.zig");
    try expectAbsent(runner, "std.Io.Dir");
    try expectAbsent(runner, "/adapters/");
    const engine = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(engine, "feature_identity");
}

test "feature document filenames and headings agree" {
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

        const source = try features.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        const heading_end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
        const heading = std.mem.trimEnd(u8, source[0..heading_end], "\r");
        const stem = entry.name[0 .. entry.name.len - ".md".len];
        const separator = std.mem.indexOfScalar(u8, stem, '-') orelse {
            return error.InvalidFeatureDocumentName;
        };
        try std.testing.expect(std.mem.startsWith(u8, heading, "# "));
        const heading_body = heading[2..];
        const heading_separator = std.mem.indexOf(u8, heading_body, " — ") orelse {
            return error.InvalidFeatureDocumentHeading;
        };
        try std.testing.expectEqualStrings(stem[0..separator], heading_body[0..heading_separator]);
        try std.testing.expectEqualStrings(stem[separator + 1 ..], heading_body[heading_separator + " — ".len ..]);
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

fn expectSingleActionContract(source: []const u8) !void {
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub const Action = struct"));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub const contract: pipeline.NodeContract"));
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
