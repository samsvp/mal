const std = @import("std");
const MalType = @import("types.zig").MalType;

pub fn prStr(allocator: std.mem.Allocator, val: MalType, print_readably: bool) void {
    _ = print_readably;
    const stdout = std.io.getStdOut().writer();
    const s = val.toString(allocator) catch unreachable;
    defer allocator.free(s);

    stdout.print("{s}\n", .{s}) catch {};
}
