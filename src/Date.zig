const std = @import("std");

const Timezone = @import("./Timezone.zig");

const Date = @This();

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

/// Creates a Date from a Unix timestamp in seconds since midnight Jan 1 1970.
pub fn fromTimestamp(timestamp: u64, timezone: Timezone) Date {
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

/// Creates a Date representing the current date and time in UTC timezone.
pub fn now() Date {
    return Date.nowWithTimezone(Timezone.UTC);
}

/// Creates a Date representing the current date and time in the provided timezone.
pub fn nowWithTimezone(timezone: Timezone) Date {
    const current_ms: u64 = @intCast(std.time.milliTimestamp());
    return Date.fromTimestamp(current_ms, timezone);
}

/// Renders the date and time in Java Date.toString format, eg. Thu Jul 18 12:43:25 AM EST 2024
pub fn writeJava(self: Date, writer: anytype) !void {
    const day_of_week_str = day_of_week_abbrev_names[self.day_of_week];
    const month_str = month_abbrev_names[self.month - 1]; // Note: self.month is 1-based
    const am_pm = if (self.hour < 12) "AM" else "PM";
    const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;
    return std.fmt.format(writer, "{s} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} {s} {s} {d}", .{ day_of_week_str, month_str, self.day, hour_12, self.minutes, self.seconds, am_pm, self.timezone.name, self.year });
}

/// Renders the date and time in ISO-8601 format, eg. 2023-10-05T15:30:00-05:00
pub fn writeISO8601(self: Date, writer: anytype) !void {
    if (self.timezone.offset_minutes == 0) {
        return std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds });
    } else {
        var buf: [8]u8 = undefined;
        const offset_str = try self.timezone.bufPrint(&buf);
        return std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{s}", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds, offset_str });
    }
}

/// Renders the date and time in Javascript toLocaleString format, eg. 7/18/2024, 12:45:52 AM
pub fn writeLocale(self: Date, writer: anytype) !void {
    const am_pm = if (self.hour < 12) "AM" else "PM";
    const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;

    return std.fmt.format(writer, "{d}/{d}/{d}, {d}:{d:0>2}:{d:0>2} {s}", .{ self.month, self.day, self.year, hour_12, self.minutes, self.seconds, am_pm });
}

/// Renders the date in ISO-8601 format, eg. 2023-10-05
pub fn writeDateISO8601(self: Date, writer: anytype) ![]u8 {
    return std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
}

/// Prints the date and time in Java Date.toString format into `buf`, eg. Thu Jul 18 12:43:25 AM EST 2024
/// Returns a slice of the bytes printed to.
pub fn bufPrintJava(self: Date, buf: []u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    self.writeJava(fbs.writer().any()) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

/// Prints the date and time in ISO-8601 format into `buf`, eg. 2023-10-05T15:30:00-05:00
/// Returns a slice of the bytes printed to.
pub fn bufPrintISO8601(self: Date, buf: []u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    self.writeISO8601(fbs.writer().any()) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

/// Prints the date and time in Javascript toLocaleString format into `buf`, eg. 7/18/2024, 12:45:52 AM
/// Returns a slice of the bytes printed to.
pub fn bufPrintLocale(self: Date, buf: []u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    self.writeLocale(fbs.writer().any()) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

/// Prints the date in ISO-8601 format into `buf`, eg. 2023-10-05
/// Returns a slice of the bytes printed to.
pub fn bufPrintDateISO8601(self: Date, buf: []u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    self.writeDateISO8601(fbs.writer().any()) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

/// Returns a buffer allocated using `allocator` filled with the date and time in Java Date.toString format, eg. Thu Jul 18 12:43:25 AM EST 2024
pub fn allocPrintJava(self: Date, allocator: std.mem.Allocator) ![]u8 {
    const day_of_week_str = day_of_week_abbrev_names[self.day_of_week];
    const month_str = month_abbrev_names[self.month - 1]; // Note: self.month is 1-based
    const am_pm = if (self.hour < 12) "AM" else "PM";
    const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;
    return std.fmt.allocPrint(allocator, "{s} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} {s} {s} {d}", .{ day_of_week_str, month_str, self.day, hour_12, self.minutes, self.seconds, am_pm, self.timezone.name, self.year });
}

/// Returns a buffer allocated using `allocator` filled with the date and time in ISO-8601 format, eg. 2023-10-05T15:30:00-05:00
pub fn allocPrintISO8601(self: Date, allocator: std.mem.Allocator) ![]u8 {
    if (self.timezone.offset_minutes == 0) {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds });
    } else {
        const offset_str = try self.timezone.allocPrint(allocator);
        defer allocator.free(offset_str);
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{s}", .{ self.year, self.month, self.day, self.hour, self.minutes, self.seconds, self.milliseconds, offset_str });
    }
}

/// Returns a buffer allocated using `allocator` filled with the date and time in Javascript toLocaleString format, eg. 7/18/2024, 12:45:52 AM
pub fn allocPrintLocale(self: Date, allocator: std.mem.Allocator) ![]u8 {
    const am_pm = if (self.hour < 12) "AM" else "PM";
    const hour_12 = if (self.hour % 12 == 0) 12 else self.hour % 12;

    return std.fmt.allocPrint(allocator, "{d}/{d}/{d}, {d}:{d:0>2}:{d:0>2} {s}", .{ self.month, self.day, self.year, hour_12, self.minutes, self.seconds, am_pm });
}

/// Returns a buffer allocated using `allocator` filled with the date in ISO-8601 format, eg. 2023-10-05
pub fn allocPrintDateISO8601(self: Date, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
}

test {}
