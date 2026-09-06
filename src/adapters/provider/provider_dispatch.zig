const interface = @import("../../ports/llm_provider_interface.zig");

pub const Dispatch = union(enum) {
    aws_bedrock: @import("aws_bedrock.zig").Provider,

    pub fn port(self: *Dispatch) interface.LLMProviderInterface {
        return switch (self.*) {
            .aws_bedrock => |*provider| provider.port(),
        };
    }
};
