const safety = @import("../domain/toolchain_safety.zig");
pub const ToolChainService = struct {
    owner: *safety.Owner,
    pub fn init(owner: *safety.Owner) ToolChainService {
        return .{ .owner = owner };
    }
    pub fn toolchain(self: *const ToolChainService) *const safety.ValidToolchain {
        return safety.value(self.owner);
    }
    pub fn deinit(self: *ToolChainService) void {
        safety.deinitOwner(self.owner);
        self.* = undefined;
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
    var service = ToolChainService.init(owner);
    defer service.deinit();
    try @import("std").testing.expect(service.toolchain() == service.toolchain());
    try @import("std").testing.expectEqualStrings("core.safety@1", service.toolchain().policies()[0].id);
}
