const std = @import("std");
const engine_config_source = @import("../adapters/filesystem/engine_config_source.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");
const bootstrap_orchestrator = @import("../application/bootstrap_orchestrator.zig");
const bootstrap_runner = @import("../application/bootstrap_runner.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator) bootstrap_orchestrator.Outcome {
    var source_adapter = engine_config_source.Adapter.init(io, .cwd());
    var runner = bootstrap_runner.Runner.init(
        allocator,
        locate.Action{ .locator = source_adapter.locator() },
        read.Action{},
        decode.Action{},
    );
    defer runner.deinit();

    return bootstrap_orchestrator.run(runner.bindings());
}
