const domain_toolchain = @import("../domain/toolchain.zig");
pub const ToolChainService = struct {
    owner: *domain_toolchain.Owner,
    pub fn init(owner: *domain_toolchain.Owner) ToolChainService {
        return .{ .owner = owner };
    }
    pub fn toolchain(self: *const ToolChainService) *const domain_toolchain.ValidToolchain {
        return domain_toolchain.value(self.owner);
    }
    pub fn deinit(self: *ToolChainService) void {
        domain_toolchain.deinitOwner(self.owner);
        self.* = undefined;
    }
};

test "exposes only the same borrowed safety-valid toolchain" {
    const owner = try domain_toolchain.validateSafety(
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
