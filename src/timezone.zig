const std = @import("std");

const Self = @This();

name: []const u8,
offset_minutes: i64,
allocator: ?std.mem.Allocator = undefined,

const UTC = Self{ .name = "UTC", .offset_minutes = 0 };

/// Fetches the system timezone on Linux using the `date` binary.
pub fn fetch(allocator: std.mem.Allocator) !Self {
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

    return Self{
        .allocator = allocator,
        .name = try allocator.dupe(u8, timezone_str),
        .offset_minutes = (hours * 60 + minutes) * sign,
    };
}

/// Deallocates the timezone when initialized with an allocator.
pub fn deinit(self: Self) void {
    if (self.allocator) |allocator| {
        allocator.free(self.name);
    }
}

/// Renders the timezone in ISO-8601 format, eg. +04:00
pub fn write(self: Self, writer: anytype) !void {
    const sign = if (self.offset_minutes < 0) "-" else "+";
    const abs_offset_minutes: u16 = @intCast(@abs(self.offset_minutes));
    const hours = abs_offset_minutes / 60;
    const minutes = abs_offset_minutes % 60;
    return std.fmt.format(writer, "{}{:02}:{:02}", .{ sign, hours, minutes });
}

/// Prints the timezone in ISO-8601 format into `buf`, eg. +04:00
pub fn bufPrint(self: Self, buf: []u8) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    self.write(fbs.writer().any()) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

/// Returns a buffer allocated using `allocator` filled with the timezone in ISO-8601 format, eg. +04:00
pub fn allocPrint(self: Self, allocator: std.mem.Allocator) ![]const u8 {
    const sign = if (self.offset_minutes < 0) "-" else "+";
    const abs_offset_minutes: u16 = @intCast(@abs(self.offset_minutes));
    const hours = abs_offset_minutes / 60;
    const minutes = abs_offset_minutes % 60;
    return std.fmt.allocPrint(allocator, "{}{:02}:{:02}", .{ sign, hours, minutes });
}
