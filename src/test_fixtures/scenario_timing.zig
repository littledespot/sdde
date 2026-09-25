//! Test-only wall-clock measurements; no workflow or test outcome authority.
const std = @import("std");

pub const Phase = enum { fixture, bootstrap, runner, execution, assertions, cleanup };
const phase_count = std.meta.fields(Phase).len;
pub const Sample = struct {
    nanoseconds: [phase_count]i96 = @splat(0),
    outcome: enum { passed, failed } = .failed,

    pub fn total(self: Sample) i96 {
        var result: i96 = 0;
        for (self.nanoseconds) |value| result += value;
        return result;
    }
};

pub const Timer = struct {
    io: std.Io,
    previous: std.Io.Clock.Timestamp,
    phase: Phase = .fixture,
    sample: Sample = .{},
    destination: *?Sample,

    pub fn start(io: std.Io, destination: *?Sample) Timer {
        return .{ .io = io, .previous = .now(io, .awake), .destination = destination };
    }

    pub fn enter(self: *Timer, phase: Phase) void {
        const now: std.Io.Clock.Timestamp = .now(self.io, .awake);
        self.sample.nanoseconds[@intFromEnum(self.phase)] += self.previous.durationTo(now).raw.toNanoseconds();
        self.previous = now;
        self.phase = phase;
    }

    pub fn passed(self: *Timer) void {
        self.sample.outcome = .passed;
        self.enter(.cleanup);
    }

    pub fn finish(self: *Timer) void {
        self.enter(self.phase);
        self.destination.* = self.sample;
    }
};

pub fn report(io: std.Io, suite: []const u8, samples: []const ?Sample) !void {
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stderr().writer(io, &buffer);
    try write(&output.interface, suite, samples);
    try output.interface.flush();
}

fn write(output: *std.Io.Writer, suite: []const u8, samples: []const ?Sample) std.Io.Writer.Error!void {
    try output.writeAll("scenario-cost\tsuite\tcase\toutcome\tfixture_ms\tbootstrap_ms\trunner_ms\texecution_ms\tassertions_ms\tcleanup_ms\ttotal_ms\n");
    var sum: Sample = .{};
    var recorded: usize = 0;
    for (samples, 0..) |entry, ordinal| {
        const sample = entry orelse continue;
        recorded += 1;
        try output.print("scenario-cost\t{s}\t{d}\t{s}", .{ suite, ordinal, @tagName(sample.outcome) });
        for (sample.nanoseconds, 0..) |value, phase| {
            sum.nanoseconds[phase] += value;
            try output.print("\t{d}", .{@divTrunc(value, std.time.ns_per_ms)});
        }
        try output.print("\t{d}\n", .{@divTrunc(sample.total(), std.time.ns_per_ms)});
    }
    try output.print("scenario-total\t{s}\t{d}/{d}\tmeasured", .{ suite, recorded, samples.len });
    for (sum.nanoseconds) |value| try output.print("\t{d}", .{@divTrunc(value, std.time.ns_per_ms)});
    try output.print("\t{d}\n", .{@divTrunc(sum.total(), std.time.ns_per_ms)});
}

test "scenario report retains phase totals failed cases and incomplete coverage" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    const ms = std.time.ns_per_ms;
    try write(&output.writer, "example", &.{
        .{ .nanoseconds = .{ 1 * ms, 2 * ms, 3 * ms, 4 * ms, 5 * ms, 6 * ms }, .outcome = .passed },
        .{ .nanoseconds = .{ 7 * ms, 8 * ms, 0, 0, 0, 0 }, .outcome = .failed },
        null,
    });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "scenario-cost\texample\t0\tpassed\t1\t2\t3\t4\t5\t6\t21\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "scenario-cost\texample\t1\tfailed\t7\t8\t0\t0\t0\t0\t15\n") != null);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "scenario-total\texample\t2/3\tmeasured\t8\t10\t3\t4\t5\t6\t36\n"));
}
