const safety = @import("../domain/toolchain_safety.zig");
pub const ToolChainService = struct {
    value: *const safety.ValidToolchain,
    pub fn init(value: *const safety.ValidToolchain) ToolChainService {
        return .{ .value = value };
    }
    pub fn toolchain(self: *const ToolChainService) *const safety.ValidToolchain {
        return self.value;
    }
};

test "exposes only the same borrowed safety-valid toolchain" {
    const owner = try safety.validate(
        @import("std").testing.allocator,
        .{ .packages = &.{}, .policies = &.{} },
        .{ .contracts = &.{
            .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
        } },
    );
    defer safety.deinitOwner(owner);
    const service = ToolChainService.init(safety.value(owner));
    try @import("std").testing.expect(service.toolchain() == service.toolchain());
    try @import("std").testing.expectEqualStrings("core.safety@1", service.toolchain().policies()[0].id);
}
