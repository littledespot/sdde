//! Bedrock Runtime endpoint projection: URL, bearer authentication and the AWS
//! response headers the shared exchange retains. No connection or capture.
const std = @import("std");
const transport = @import("model_http_transport.zig");

pub const Target = @FieldType(transport.Target, "aws_bedrock");

pub fn project(allocator: std.mem.Allocator, target: Target, api_key: []const u8) std.mem.Allocator.Error!transport.Projection {
    return .{
        .url = try url(allocator, target),
        .authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key}),
    };
}

pub fn url(allocator: std.mem.Allocator, target: Target) std.mem.Allocator.Error![]const u8 {
    var encoded: std.Io.Writer.Allocating = .init(allocator);
    defer encoded.deinit();
    for (target.model.bytes) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            encoded.writer.writeByte(byte) catch return error.OutOfMemory;
        } else {
            encoded.writer.print("%{X:0>2}", .{byte}) catch return error.OutOfMemory;
        }
    }
    // Region is a closed enum, not a user-supplied host or URL string.
    return std.fmt.allocPrint(allocator, "https://bedrock-runtime.{s}.amazonaws.com/model/{s}/{s}", .{
        @tagName(target.region), encoded.written(), if (target.kind == .inference) "converse" else "count-tokens",
    });
}

pub fn retained(name: []const u8) ?transport.RetainedHeader {
    if (std.ascii.eqlIgnoreCase(name, "x-amzn-errortype")) return .exception;
    if (std.ascii.eqlIgnoreCase(name, "x-amzn-requestid")) return .request_id;
    return null;
}
