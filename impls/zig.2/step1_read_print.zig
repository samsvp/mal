const std = @import("std");
const Linenoise = @import("linenoize").Linenoise;

const MalType = @import("types.zig").MalType;
const Reader = @import("reader.zig");

fn read(allocator: std.mem.Allocator, s: []const u8) MalType {
    return Reader.readStr(allocator, s) catch @panic("wat");
}

fn eval(s: MalType) MalType {
    return s;
}

fn print(s: MalType) []const u8 {
    return s.toString();
}

fn rep(allocator: std.mem.Allocator, s: []const u8) []const u8 {
    return print(
        eval(
            read(
                allocator,
                s,
            ),
        ),
    );
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    while (try ln.linenoise("user> ")) |input| {
        defer allocator.free(input);
        const res = rep(allocator, input);
        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}
