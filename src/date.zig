const std = @import("std");

const Date = struct {
    timestamp: u64,
    timezone: Timezone,

    // timezone-dependent fields
    year: u64,
    month: u64,
    day: u64,
    hour: u64,
    minutes: u64,
    seconds: u64,
    milliseconds: u64,
    day_of_week: u8,

    const day_of_week_abbrev_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    const month_abbrev_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    const Timezone = struct {
        name: []const u8,
        offset_minutes: i64,
        allocator: ?std.mem.Allocator = undefined,

        const UTC = Timezone{ .name = "UTC", .offset_minutes = 0 };

        fn fetch(allocator: std.mem.Allocator) !Timezone {
            const result = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &[_][]const u8{ "date", "+%z %Z" },
            });
            defer allocator.free(result.stderr);
            defer allocator.free(result.stdout);

            if (result.term.Exited != 0) {
                return error.DateCommandFailed;
            }

            const output = std.mem.trimRight(u8, result.stdout, "\n");
            var iter = std.mem.splitSequence(u8, output, " ");
            const offset_str = iter.next() orelse return error.InvalidOutput;
            const timezone_str = iter.next() orelse return error.InvalidOutput;

            if (offset_str.len != 5) {
                return error.InvalidOffsetFormat;
            }

            const sign: i16 = if (offset_str[0] == '-') -1 else 1;
            const hours = try std.fmt.parseInt(i16, offset_str[1..3], 10);
            const minutes = try std.fmt.parseInt(i16, offset_str[3..5], 10);

            return Timezone{
                .allocator = allocator,
                .name = try allocator.dupe(u8, timezone_str),
                .offset_minutes = (hours * 60 + minutes) * sign,
            };
        }

        fn deinit(self: Timezone) void {
            if (self.allocator) |allocator| {
                allocator.free(self.name);
            }
        }

        fn write(self: Timezone, writer: anytype) !void {
            const sign = if (self.offset_minutes < 0) "-" else "+";
            const abs_offset_minutes: u16 = @intCast(@abs(self.offset_minutes));
            const hours = abs_offset_minutes / 60;
            const minutes = abs_offset_minutes % 60;
            return std.fmt.format(writer, "{}{:02}:{:02}", .{ sign, hours, minutes });
        }

        fn bufPrint(self: Timezone, buf: []u8) ![]u8 {
            var fbs = std.io.fixedBufferStream(buf);
            self.write(fbs.writer().any()) catch |err| switch (err) {
                error.NoSpaceLeft => return error.NoSpaceLeft,
                else => unreachable,
            };
            return fbs.getWritten();
        }

        fn allocPrint(self: Timezone, allocator: std.mem.Allocator) ![]const u8 {
            const sign = if (self.offset_minutes < 0) "-" else "+";
            const abs_offset_minutes: u16 = @intCast(@abs(self.offset_minutes));
            const hours = abs_offset_minutes / 60;
            const minutes = abs_offset_minutes % 60;
            return std.fmt.allocPrint(allocator, "{}{:02}:{:02}", .{ sign, hours, minutes });
        }
    };

    fn fromTimestamp(timestamp: u64, timezone: Timezone) Date {
        const offset_ms = timezone.offset_minutes * 60 * 1_000;
        var offset_timestamp: u64 = undefined;
        if (offset_ms > 0) {
            offset_timestamp = timestamp + @as(u64, @intCast(offset_ms));
        } else {
            offset_timestamp = timestamp - @as(u64, @intCast(offset_ms * -1));
        }

        const ms_per_sec: u64 = 1000;
        const ms_per_minute: u64 = 60 * ms_per_sec;
        const ms_per_hour: u64 = 60 * ms_per_minute;
        const ms_per_day: u64 = 24 * ms_per_hour;
        const days_since_epoch = offset_timestamp / ms_per_day;

        var year: u64 = 1970;
        var day_of_year: u64 = days_since_epoch;
        var leap_year: bool = false;

        while (true) {
            leap_year = (year % 4 == 0) and (year % 100 != 0) or (year % 400 == 0);
            const days_in_year: u64 = if (leap_year) 366 else 365;
            if (day_of_year < days_in_year) break;
            day_of_year -= days_in_year;
            year += 1;
        }

        const day_of_month_table = [_][12]u64{
            // Non-leap year
            [_]u64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
            // Leap year
            [_]u64{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
        };

        var month: u64 = 0;
        var day_of_month: u64 = day_of_year;
        while (day_of_month >= day_of_month_table[if (leap_year) 1 else 0][month]) {
            day_of_month -= day_of_month_table[if (leap_year) 1 else 0][month];
            month += 1;
        }

        const ms_in_day = offset_timestamp % ms_per_day;
        const hour = ms_in_day / ms_per_hour;
        const minutes = (ms_in_day % ms_per_hour) / ms_per_minute;
        const seconds = (ms_in_day % ms_per_minute) / ms_per_sec;
        const milliseconds = ms_in_day % ms_per_sec;

        const day_of_week: u8 = @intCast((days_since_epoch + 4) % 7); // 1970-01-01 is a Thursday, which is the 4th day of the week

        return Date{
            .timestamp = timestamp,
            .year = year,
            .month = month + 1,
            .day = day_of_month + 1,
            .hour = hour,
            .minutes = minutes,
            .seconds = seconds,
            .milliseconds = milliseconds,
            .day_of_week = day_of_week,
            .timezone = timezone,
        };
    }

    fn now() Date {
        return Date.nowWithTimezone(Timezone.UTC);
    }

    fn nowWithTimezone(timezone: Timezone) Date {
        const current_ms: u64 = @intCast(std.time.milliTimestamp());
        return Date.fromTimestamp(current_ms, timezone);
    }

    fn writeJava(self: Date, writer: anytype) !void {
        const day_of_week_str = day_of_week_abbrev_names[self.day_of_week];
        const month_str = month_abbrev_names[self.month - 1]; // Note: self.month is 1-based
        const am_pm = if (self.hour < 12) "AM" else "PM";
        const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;
        return std.fmt.format(writer, "{s} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} {s} {s} {d}", .{ day_of_week_str, month_str, self.day, hour_12, self.minutes, self.seconds, am_pm, self.timezone.name, self.year });
    }

    fn writeISO8601(self: Date, writer: anytype) !void {
        if (self.timezone.offset_minutes == 0) {
            return std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds });
        } else {
            var buf: [8]u8 = undefined;
            const offset_str = try self.timezone.bufPrint(&buf);
            return std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{s}", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds, offset_str });
        }
    }

    fn writeLocale(self: Date, writer: anytype) !void {
        const am_pm = if (self.hour < 12) "AM" else "PM";
        const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;

        return std.fmt.format(writer, "{d}/{d}/{d}, {d}:{d:0>2}:{d:0>2} {s}", .{ self.month, self.day, self.year, hour_12, self.minutes, self.seconds, am_pm });
    }

    fn writeDateISO8601(self: Date, writer: anytype) ![]u8 {
        return std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }

    fn bufPrintJava(self: Date, buf: []u8) ![]u8 {
        var fbs = std.io.fixedBufferStream(buf);
        self.writeJava(fbs.writer().any()) catch |err| switch (err) {
            error.NoSpaceLeft => return error.NoSpaceLeft,
            else => unreachable,
        };
        return fbs.getWritten();
    }

    fn bufPrintISO8601(self: Date, buf: []u8) ![]u8 {
        var fbs = std.io.fixedBufferStream(buf);
        self.writeISO8601(fbs.writer().any()) catch |err| switch (err) {
            error.NoSpaceLeft => return error.NoSpaceLeft,
            else => unreachable,
        };
        return fbs.getWritten();
    }

    fn bufPrintLocale(self: Date, buf: []u8) ![]u8 {
        var fbs = std.io.fixedBufferStream(buf);
        self.writeLocale(fbs.writer().any()) catch |err| switch (err) {
            error.NoSpaceLeft => return error.NoSpaceLeft,
            else => unreachable,
        };
        return fbs.getWritten();
    }

    fn bufPrintDateISO8601(self: Date, buf: []u8) ![]u8 {
        var fbs = std.io.fixedBufferStream(buf);
        self.writeDateISO8601(fbs.writer().any()) catch |err| switch (err) {
            error.NoSpaceLeft => return error.NoSpaceLeft,
            else => unreachable,
        };
        return fbs.getWritten();
    }

    // Java Date toString format
    fn allocPrintJava(self: Date, allocator: std.mem.Allocator) ![]u8 {
        const day_of_week_str = day_of_week_abbrev_names[self.day_of_week];
        const month_str = month_abbrev_names[self.month - 1]; // Note: self.month is 1-based
        const am_pm = if (self.hour < 12) "AM" else "PM";
        const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;
        return std.fmt.allocPrint(allocator, "{s} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} {s} {s} {d}", .{ day_of_week_str, month_str, self.day, hour_12, self.minutes, self.seconds, am_pm, self.timezone.name, self.year });
    }

    fn allocPrintISO8601(self: Date, allocator: std.mem.Allocator) ![]u8 {
        if (self.timezone.offset_minutes == 0) {
            return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds });
        } else {
            const offset_str = try self.timezone.allocPrint(allocator);
            defer allocator.free(offset_str);
            return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{s}", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds, offset_str });
        }
    }

    fn allocPrintLocale(self: Date, allocator: std.mem.Allocator) ![]u8 {
        const am_pm = if (self.hour < 12) "AM" else "PM";
        const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;

        return std.fmt.allocPrint(allocator, "{d}/{d}/{d}, {d}:{d:0>2}:{d:0>2} {s}", .{ self.month, self.day, self.year, hour_12, self.minutes, self.seconds, am_pm });
    }

    fn allocPrintDateISO8601(self: Date, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }
};
