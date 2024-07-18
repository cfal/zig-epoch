const std = @import("std");

const Timezone = @This();

name: []const u8,
offset_minutes: i64,
allocator: ?std.mem.Allocator = null,

pub const GMT = Timezone{ .name = "GMT", .offset_minutes = 0 };

/// Fetches the system timezone on Linux using the `date` binary.
pub fn fetch(allocator: std.mem.Allocator) !Timezone {
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

/// Parses a string representation of a timezone offset into a Timezone struct.
/// If `name` is not specified, then `str` is used as the timezone name.
/// If `allocator is specified, `Timezone.deinit()` will free the string used as the name.
/// Supported formats: +/-HHMM, +/-HH:MM, +/-H:MM. Defaults to positive (+) offset if
/// not prefixed by a sign.
pub fn fromString(str: []const u8, name: ?[]const u8, allocator: ?std.mem.Allocator) !Timezone {
    if (str.len < 3 or str.len > 6) return error.InvalidFormat;

    var sign: i8 = 1;
    var start_index: usize = 0;

    if (str[0] == '-') {
        sign = -1;
        start_index = 1;
    } else if (str[0] == '+') {
        start_index = 1;
    }

    var hours: u8 = undefined;
    var minutes: u8 = undefined;

    if (std.mem.indexOf(u8, str, ":")) |colon_index| {
        hours = try std.fmt.parseInt(u8, str[start_index..colon_index], 10);
        minutes = try std.fmt.parseInt(u8, str[colon_index + 1 ..], 10);
    } else {
        const parsed = try std.fmt.parseInt(u16, str[start_index..], 10);
        hours = @intCast(parsed / 100);
        minutes = @intCast(parsed % 100);
    }

    if (hours > 23 or minutes > 59) return error.InvalidTime;

    return Timezone{
        .name = name orelse str,
        .offset_minutes = @as(i64, @intCast(sign)) * (@as(i64, @intCast(hours)) * 60 + @as(i64, @intCast(minutes))),
        .allocator = allocator,
    };
}

/// Deallocates the timezone when initialized with an allocator.
pub fn deinit(self: Timezone) void {
    if (self.allocator) |allocator| {
        allocator.free(self.name);
    }
}

/// Renders the timezone in ISO-8601 format, eg. +04:00
pub fn write(self: Timezone, writer: anytype) !void {
    const sign = if (self.offset_minutes < 0) "-" else "+";
    const abs_offset_minutes: u16 = @intCast(@abs(self.offset_minutes));
    const hours = abs_offset_minutes / 60;
    const minutes = abs_offset_minutes % 60;
    return std.fmt.format(writer, "{s}{:02}:{:02}", .{ sign, hours, minutes });
}

/// Prints the timezone in ISO-8601 format into `buf`, eg. +04:00
pub fn bufPrint(self: Timezone, buf: []u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    self.write(fbs.writer().any()) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

/// Returns a buffer allocated using `allocator` filled with the timezone in ISO-8601 format, eg. +04:00
pub fn allocPrint(self: Timezone, allocator: std.mem.Allocator) ![]const u8 {
    const sign = if (self.offset_minutes < 0) "-" else "+";
    const abs_offset_minutes: u16 = @intCast(@abs(self.offset_minutes));
    const hours = abs_offset_minutes / 60;
    const minutes = abs_offset_minutes % 60;
    return std.fmt.allocPrint(allocator, "{s}{:02}:{:02}", .{ sign, hours, minutes });
}

test "fromString negative" {
    for ([_][]const u8{ "-04:33", "-4:33", "-0433", "-433" }) |s| {
        const name = try testing.allocator.alloc(u8, 4);
        @memcpy(name, "ABCD");
        const t = try Timezone.fromString(s, name, testing.allocator);
        defer t.deinit();
        try testing.expectEqual(-4 * 60 - 33, t.offset_minutes);
        try testing.expectEqual(name, t.name);
    }
}

test "fromString negative double-digit" {
    for ([_][]const u8{ "-11:33", "-1133" }) |s| {
        const name = try testing.allocator.alloc(u8, 4);
        @memcpy(name, "ABCD");
        const t = try Timezone.fromString(s, name, testing.allocator);
        defer t.deinit();
        try testing.expectEqual(-11 * 60 - 33, t.offset_minutes);
        try testing.expectEqual(name, t.name);
    }
}

test "fromString positive" {
    for ([_][]const u8{ "+08:55", "+8:55", "+0855", "+855", "08:55", "8:55", "0855", "855" }) |s| {
        const name = try testing.allocator.alloc(u8, 4);
        @memcpy(name, "EFGH");
        const t = try Timezone.fromString(s, name, testing.allocator);
        defer t.deinit();
        try testing.expectEqual(8 * 60 + 55, t.offset_minutes);
        try testing.expectEqual(name, t.name);
    }
}

test "fromString positive double-digit" {
    for ([_][]const u8{ "+11:55", "+1155", "11:55", "1155" }) |s| {
        const name = try testing.allocator.alloc(u8, 4);
        @memcpy(name, "EFGH");
        const t = try Timezone.fromString(s, name, testing.allocator);
        defer t.deinit();
        try testing.expectEqual(11 * 60 + 55, t.offset_minutes);
        try testing.expectEqual(name, t.name);
    }
}

test "allocPrint" {
    const expected = "+11:22";
    const t = try Timezone.fromString(expected, null, null);
    const actual = try t.allocPrint(testing.allocator);
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, expected, actual);
}
