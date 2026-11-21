//! The typed facts of a failed model call that the run report and the CLI show (F0006 §8). Every member
//! is a member of a closed set with no text of its own, so no key, header, body or provider message can
//! reach it. It is presentation data: no tag, code or branch is chosen from it, and the failure's own
//! cause, retry class and delivery keep their meaning in the provider contract.
const std = @import("std");
const provider = @import("llm_provider_operation.zig");

pub const Detail = struct {
    cause: provider.ProviderFailureCause,
    retry_class: provider.ProviderRetryClass,
    delivery: provider.ProviderDeliveryDisposition,
    /// Where and how the shared HTTP exchange failed, when it did.
    transport: ?provider.TransportDiagnostic = null,
    content: ?provider.ProviderContentDiagnostic = null,
    credential: ?provider.ProviderCredentialDiagnostic = null,
    decode: ?provider.ProviderDecodeDiagnostic = null,

    pub fn from(failure: provider.ProviderFailure) Detail {
        return .{
            .cause = failure.cause,
            .retry_class = failure.retry_class,
            .delivery = failure.delivery,
            .transport = failure.transport,
            .content = failure.content,
            .credential = failure.credential,
            .decode = failure.decode,
        };
    }

    /// `provider_failure: <cause>; delivery=<d>; retry=<r>[; transport=<phase>/<cause>][; content=<c>][; credential=<c>][; decode=<d>]`.
    pub fn write(self: Detail, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("provider_failure: {s}; delivery={s}; retry={s}", .{ @tagName(self.cause), @tagName(self.delivery), @tagName(self.retry_class) });
        if (self.transport) |transport| try writer.print("; transport={s}/{s}", .{ @tagName(transport.phase), @tagName(transport.cause) });
        if (self.content) |content| try writer.print("; content={s}", .{@tagName(content)});
        if (self.credential) |credential| try writer.print("; credential={s}", .{@tagName(credential)});
        if (self.decode) |decode| try writer.print("; decode={s}", .{@tagName(decode)});
    }
};

test "each cause, delivery and retry class prints its own name, so no two failures read alike" {
    var buffer: [160]u8 = undefined;
    inline for (std.enums.values(provider.ProviderFailureCause)) |cause| {
        inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
            inline for (std.enums.values(provider.ProviderRetryClass)) |retry_class| {
                var writer: std.Io.Writer = .fixed(&buffer);
                try (Detail{ .cause = cause, .retry_class = retry_class, .delivery = delivery }).write(&writer);
                const expected = "provider_failure: " ++ @tagName(cause) ++ "; delivery=" ++ @tagName(delivery) ++ "; retry=" ++ @tagName(retry_class);
                try std.testing.expectEqualStrings(expected, writer.buffered());
            }
        }
    }
}

test "a credential reason and a decode reason print their own names, and only when the failure carries one" {
    var buffer: [200]u8 = undefined;
    inline for (std.enums.values(provider.ProviderCredentialDiagnostic)) |credential| {
        var writer: std.Io.Writer = .fixed(&buffer);
        try (Detail{ .cause = .authentication_failed, .retry_class = .never, .delivery = .not_sent, .credential = credential }).write(&writer);
        try std.testing.expectEqualStrings("provider_failure: authentication_failed; delivery=not_sent; retry=never; credential=" ++ @tagName(credential), writer.buffered());
    }
    inline for (std.enums.values(provider.ProviderDecodeDiagnostic)) |decode| {
        var writer: std.Io.Writer = .fixed(&buffer);
        try (Detail{ .cause = .response_invalid, .retry_class = .never, .delivery = .response_received, .decode = decode }).write(&writer);
        try std.testing.expectEqualStrings("provider_failure: response_invalid; delivery=response_received; retry=never; decode=" ++ @tagName(decode), writer.buffered());
    }
}

test "a transport diagnostic and a content diagnostic print only when the failure carries one" {
    var buffer: [200]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    const detail: Detail = .{
        .cause = .transport_failed,
        .retry_class = .policy_eligible,
        .delivery = .accepted_or_unknown,
        .transport = .{ .phase = .connecting, .cause = .name_resolution },
        .content = .missing_final_text,
    };
    try detail.write(&writer);
    try std.testing.expectEqualStrings("provider_failure: transport_failed; delivery=accepted_or_unknown; retry=policy_eligible; transport=connecting/name_resolution; content=missing_final_text", writer.buffered());
    writer = .fixed(&buffer);
    var bare = detail;
    bare.transport = null;
    bare.content = null;
    try bare.write(&writer);
    try std.testing.expectEqualStrings("provider_failure: transport_failed; delivery=accepted_or_unknown; retry=policy_eligible", writer.buffered());
}
