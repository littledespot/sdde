//! Explicit offline protocol fixtures. They are never substituted into a live
//! case, nor do they amend the current shipped provider configuration.
const std = @import("std");
const contracts = @import("../harness/e2e/contracts.zig");

pub const config_source = "test/integration/fixtures/baseline/protocol.sddtoolkit.json";
pub const template_case = "test/integration/fixtures/baseline/protocol.workflow.case.json";
/// MOCK bad input, never runtime configuration: the protocol configuration with
/// one still-bound control changed (the generation slot's reasoning effort). Tests
/// use it to prove the frozen binding rejects drift before any billed send.
pub const mock_bad_input_config_source = "test/integration/fixtures/baseline/mock-bad-input-drifted-effort.sddtoolkit.json";

pub fn select(a: std.mem.Allocator, source: contracts.Case) !contracts.Case {
    const bytes = try @import("../harness/files.zig").read(std.testing.io, a, .cwd(), config_source);
    // The immutable protocol validator proves the fixture's generation slot,
    // provider, model and reasoning effort before use.
    try @import("../harness/compatibility/cli.zig").preflight(a, bytes);
    var selected = source;
    selected.config = config_source;
    return selected;
}
