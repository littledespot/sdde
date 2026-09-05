const toolchain = @import("../domain/toolchain.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");

/// The same registered policy descriptors serve safety and lexical consumers.
/// YAML selects policy IDs; package names are never interpreted as rules.
pub const registry: toolchain.PolicyRegistry = .{ .contracts = &.{
    .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true, .naming = &.{
        .{ .id = .{ .bytes = "core.config" }, .kind = .reserved, .value = @import("../domain/config.zig").engine_config_basename, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.providers" }, .kind = .reserved, .value = @import("../domain/bootstrap_roots.zig").llm_provider_config_basename, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.toolchain" }, .kind = .reserved, .value = toolchain.project_filename, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.workflow" }, .kind = .extension, .value = @import("../domain/workflow_inventory.zig").definition_suffix, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.preset" }, .kind = .extension, .value = toolchain.preset_suffix, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.specification" }, .kind = .reserved, .value = artifacts.specification_filename, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.reference-context" }, .kind = .reserved, .value = artifacts.reference_context_filename, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.clarification-state" }, .kind = .reserved, .value = artifacts.clarification_state_filename, .case_sensitive = true },
        .{ .id = .{ .bytes = "core.workflow-state" }, .kind = .reserved, .value = artifacts.workflow_state_filename, .case_sensitive = true },
    } },
    .{ .id = "project.zig@1", .project_selectable = true, .locked_required = false, .naming = &.{
        .{ .id = .{ .bytes = "zig.source" }, .kind = .extension, .value = ".zig", .case_sensitive = true },
        .{ .id = .{ .bytes = "zig.manifest" }, .kind = .manifest, .value = "build.zig.zon", .case_sensitive = true },
    } },
} };
