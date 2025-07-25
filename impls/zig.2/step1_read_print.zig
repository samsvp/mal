const std = @import("std");
const Linenoise = @import("linenoize").Linenoise;

const MalType = @import("types.zig").MalType;
const Reader = @import("reader.zig");

fn read(allocator: std.mem.Allocator, s: []const u8) !MalType {
    return try Reader.readStr(allocator, s);
}

fn eval(allocator: std.mem.Allocator, s: MalType) MalType {
    _ = allocator;
    return s;
}

fn print(allocator: std.mem.Allocator, s: MalType) []const u8 {
    return s.toString(allocator) catch "Could not build string.";
}

fn rep(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const val = try read(
        allocator,
        s,
    );
    return print(
        allocator,
        eval(
            allocator,
            val,
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
        const res = rep(allocator, input) catch |err| {
            try stdout.print("{any}\n", .{err});
            continue;
        };
        defer allocator.free(res);

        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}
