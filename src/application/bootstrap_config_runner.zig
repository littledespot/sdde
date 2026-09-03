const std = @import("std");
const config = @import("../domain/config.zig");
const log_policy = @import("../domain/log_policy.zig");
const engine_config_source = @import("../ports/engine_config_source.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");
const canonicalize_log_level = @import("../actions/log/canonicalize_log_level.zig");
const validate_logging_policy = @import("../actions/log/validate_logging_policy.zig");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const pipeline = @import("../domain/pipeline.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const execution = @import("bootstrap_execution.zig");

comptime {
    pipeline.validateLinear(
        &.{.invocation_working_directory},
        &.{
            locate.Action.contract,
            read.Action.contract,
            decode.Action.contract,
            canonicalize_log_level.Action.contract,
            validate_logging_policy.Action.contract,
        },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    execution: *execution.State,
    locate_action: locate.Action,
    read_action: read.Action,
    decode_action: decode.Action,
    canonicalize_log_level_action: canonicalize_log_level.Action,
    validate_logging_policy_action: validate_logging_policy.Action,
    exact_config_file: ?engine_config_source.ExactEngineConfigFile = null,
    raw_config: ?engine_config_source.RawEngineConfig = null,
    decoded_config: ?config.Owned = null,
    canonicalized_log_level: ?log_policy.CanonicalizedLevel = null,
    validated_log_owner: ?*log_policy.Owner = null,

    pub fn init(
        allocator: std.mem.Allocator,
        execution_state: *execution.State,
        locate_action: locate.Action,
        read_action: read.Action,
        decode_action: decode.Action,
        canonicalize_log_level_action: canonicalize_log_level.Action,
        validate_logging_policy_action: validate_logging_policy.Action,
    ) Runner {
        return .{
            .allocator = allocator,
            .execution = execution_state,
            .locate_action = locate_action,
            .read_action = read_action,
            .decode_action = decode_action,
            .canonicalize_log_level_action = canonicalize_log_level_action,
            .validate_logging_policy_action = validate_logging_policy_action,
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.validated_log_owner) |owner| log_policy.deinitOwner(owner);
        if (self.decoded_config) |*owned| owned.deinit();
        if (self.raw_config) |*raw| raw.deinit(self.allocator);
        if (self.exact_config_file) |*exact| exact.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn invokeLocate(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(locate.Action.contract, .ENGINE_CONFIG_READ_ERROR)) |outcome| return outcome;
        std.debug.assert(self.exact_config_file == null);
        self.exact_config_file = self.locate_action.execute(self.allocator) catch return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
        return self.execution.finish(locate.Action.contract, .ENGINE_CONFIG_READ_ERROR);
    }

    pub fn invokeRead(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(read.Action.contract, .ENGINE_CONFIG_READ_ERROR)) |outcome| return outcome;
        std.debug.assert(self.exact_config_file != null);
        std.debug.assert(self.raw_config == null);
        self.raw_config = self.read_action.execute(&self.exact_config_file.?, self.allocator) catch return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
        return self.execution.finish(read.Action.contract, .ENGINE_CONFIG_READ_ERROR);
    }

    pub fn invokeDecode(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(decode.Action.contract, .ENGINE_CONFIG_PARSE_ERROR)) |outcome| return outcome;
        std.debug.assert(self.raw_config != null);
        std.debug.assert(self.decoded_config == null);
        self.decoded_config = self.decode_action.execute(self.allocator, self.raw_config.?.bytes) catch return .{ .failed = .ENGINE_CONFIG_PARSE_ERROR };
        return self.execution.finish(decode.Action.contract, .ENGINE_CONFIG_PARSE_ERROR);
    }

    pub fn invokeCanonicalizeLogLevel(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(canonicalize_log_level.Action.contract, .LOGGING_POLICY_INVALID)) |outcome| return outcome;
        std.debug.assert(self.decoded_config != null);
        std.debug.assert(self.canonicalized_log_level == null);
        self.canonicalized_log_level = self.canonicalize_log_level_action.execute(
            self.decoded_config.?.value().logs.level,
        ) catch return .{ .failed = .LOGGING_POLICY_INVALID };
        return self.execution.finish(canonicalize_log_level.Action.contract, .LOGGING_POLICY_INVALID);
    }

    pub fn invokeValidateLoggingPolicy(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_logging_policy.Action.contract, .LOGGING_POLICY_INVALID)) |outcome| return outcome;
        std.debug.assert(self.decoded_config != null);
        std.debug.assert(self.canonicalized_log_level != null);
        std.debug.assert(self.validated_log_owner == null);
        self.validated_log_owner = self.validate_logging_policy_action.execute(
            self.allocator,
            self.decoded_config.?.value().logs,
            self.canonicalized_log_level.?,
        ) catch return .{ .failed = .LOGGING_POLICY_INVALID };
        return self.execution.finish(validate_logging_policy.Action.contract, .LOGGING_POLICY_INVALID);
    }

    pub fn configValue(self: *const Runner) *const config.SDDToolKitConfig {
        return self.decoded_config.?.value();
    }

    pub fn exactConfigFile(self: *const Runner) *const engine_config_source.ExactEngineConfigFile {
        return &self.exact_config_file.?;
    }

    pub fn takeConfig(self: *Runner) config.Owned {
        const owned = self.decoded_config.?;
        self.decoded_config = null;
        return owned;
    }

    pub fn takeLoggingPolicy(self: *Runner) *log_policy.Owner {
        const owner = self.validated_log_owner.?;
        self.validated_log_owner = null;
        return owner;
    }
};
