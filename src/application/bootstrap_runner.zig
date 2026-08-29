const std = @import("std");
const config = @import("../domain/config.zig");
const pipeline = @import("../domain/pipeline.zig");
const source = @import("../ports/engine_config_source.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const config_registry = @import("config_registry.zig");

comptime {
    pipeline.validateLinear(
        &.{.invocation_working_directory},
        &.{
            locate.Action.contract,
            read.Action.contract,
            decode.Action.contract,
        },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    locate_action: locate.Action,
    read_action: read.Action,
    decode_action: decode.Action,
    exact_config: ?source.ExactEngineConfig = null,
    raw_config: ?source.RawEngineConfig = null,
    decoded_config: ?config.Owned = null,

    pub fn init(
        allocator: std.mem.Allocator,
        locate_action: locate.Action,
        read_action: read.Action,
        decode_action: decode.Action,
    ) Runner {
        return .{
            .allocator = allocator,
            .locate_action = locate_action,
            .read_action = read_action,
            .decode_action = decode_action,
        };
    }

    pub fn bindings(self: *Runner) child_bindings.ChildBindings {
        return .{
            .context = self,
            .vtable = &bindings_vtable,
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.decoded_config) |*owned| owned.deinit();
        if (self.raw_config) |*raw| raw.deinit(self.allocator);
        if (self.exact_config) |*exact| exact.deinit(self.allocator);
        self.* = undefined;
    }

    fn invokeLocate(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        std.debug.assert(self.exact_config == null);

        self.exact_config = self.locate_action.execute(self.allocator) catch {
            return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
        };
        return .ok;
    }

    fn invokeRead(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        std.debug.assert(self.exact_config != null);
        std.debug.assert(self.raw_config == null);

        self.raw_config = self.read_action.execute(
            &self.exact_config.?,
            self.allocator,
        ) catch {
            return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
        };
        return .ok;
    }

    fn invokeDecode(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        std.debug.assert(self.raw_config != null);
        std.debug.assert(self.decoded_config == null);

        self.decoded_config = self.decode_action.execute(
            self.allocator,
            self.raw_config.?.bytes,
        ) catch {
            return .{ .failed = .ENGINE_CONFIG_PARSE_ERROR };
        };
        return .ok;
    }

    fn takeRegistry(context: *anyopaque) config_registry.Registry {
        const self: *Runner = @ptrCast(@alignCast(context));
        const owned = self.decoded_config.?;
        self.decoded_config = null;
        return .init(owned);
    }
};

const bindings_vtable: child_bindings.ChildBindings.VTable = .{
    .locate = Runner.invokeLocate,
    .read = Runner.invokeRead,
    .decode = Runner.invokeDecode,
    .take_registry = Runner.takeRegistry,
};
