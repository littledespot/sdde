const std = @import("std");
const log_stream = @import("../../domain/feature_log_stream.zig");
const clock_port = @import("../../ports/trusted_log_clock.zig");

pub const Adapter = struct {
    io: std.Io,

    pub fn clock(self: *Adapter) clock_port.Clock {
        return .{ .context = self, .now_fn = now };
    }

    fn now(context: *anyopaque) clock_port.Error!log_stream.ClockReading {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const real_ms = std.Io.Clock.now(.real, self.io).toMilliseconds();
        const monotonic_ms = std.Io.Clock.now(.boot, self.io).toMilliseconds();
        if (real_ms < 0 or monotonic_ms < 0) return error.ClockFailure;
        const seconds: u64 = @intCast(@divTrunc(real_ms, 1000));
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
        const year_day = epoch_seconds.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch_seconds.getDaySeconds();
        var reading: log_stream.ClockReading = .{
            .occurred_at_utc = undefined,
            .unix_ms = @intCast(real_ms),
            .monotonic_ms = @intCast(monotonic_ms),
        };
        const rendered = std.fmt.bufPrint(
            &reading.occurred_at_utc,
            "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
            .{
                year_day.year,
                @intFromEnum(month_day.month),
                month_day.day_index + 1,
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
            },
        ) catch return error.ClockFailure;
        if (rendered.len != reading.occurred_at_utc.len) return error.ClockFailure;
        return reading;
    }
};
