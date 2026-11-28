const std = @import("std");

/// The closed set of operational capabilities a registered operation can hold. A capability derives
/// only from the narrow ports an operation's binding reaches, and a workflow policy bounds it. This
/// declaration order is the order a binding lists its capabilities in.
pub const Capability = enum {
    feature_logging,
    model_provider,
    provider_authorization,
    principle_read,
    toolchain_read,
    toolchain_parser,
    reference_read,
    feature_read,
    feature_input_read,
    feature_output_write,
    reference_content_read,
    reference_decode,
    reference_identity,
    actor_authentication,
};

pub const Set = std.enums.EnumSet(Capability);

pub fn contains(capabilities: []const Capability, expected: Capability) bool {
    for (capabilities) |capability| if (capability == expected) return true;
    return false;
}

pub fn unique(capabilities: []const Capability) bool {
    for (capabilities, 0..) |capability, index| {
        if (contains(capabilities[0..index], capability)) return false;
    }
    return true;
}

pub fn permits(ceiling: []const Capability, required: []const Capability) bool {
    for (required) |capability| if (!contains(ceiling, capability)) return false;
    return true;
}
