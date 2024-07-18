# zig-epoch

Yet another date and time library for Zig.

## Docs

Docs can be generated using `zig build docs`. It'll be hosted on Github Pages at some point.

## Example

```zig
const std = @import("std");
const epoch = @import("epoch");
const Date = epoch.Date;
const Timezone = epoch.Timezone;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Fetch the timezone on Linux using the `date` CLI.
    const timezone = try Timezone.fetch(allocator);
    defer timezone.deinit();
    const offset_str = try timezone.allocPrint(allocator);
    std.debug.print("The timezone is: {s} {s}\n", .{ timezone.name, offset_str });
    // The timezone is: SGT +08:00

    // Create a date in a specific timezone (or Date.now(null) to default to UTC)
    const now = Date.now(timezone);

    // Render in various formats
    const locale_str = try now.allocPrintLocale(allocator);
    std.debug.print("allocPrintLocale: {s}\n", .{locale_str});
    // allocPrintLocale: 7/18/2024, 8:48:23 PM

    const java_str = try now.allocPrintJava(allocator);
    std.debug.print("allocPrintJava: {s}\n", .{java_str});
    // allocPrintJava: Thu Jul 18 08:48:23 PM SGT 2024

    const iso8601_str = try now.allocPrintISO8601(allocator);
    std.debug.print("allocPrintISO8601: {s}\n", .{iso8601_str});
    // allocPrintISO8601: 2024-07-18T20:48:23.828+08:00

    // Convert into a UNIX timestamp
    std.debug.print("The UNIX timestamp is: {d}\n", .{now.toTimestamp()});
    // The UNIX timestamp is: 1721306903828

    // Convert from a UNIX timestamp, optionally with a target timezone.
    const epoch = Date.fromTimestamp(0, Timezone.GMT);
    // Print using the buffer or writer API
    var epoch_buffer: [80]u8 = undefined;
    std.debug.print("The epoch date is: {s}\n", .{try epoch.bufPrintISO8601(&epoch_buffer)});
    // The epoch date is: 1970-01-01T00:00:00.000Z
}
```
