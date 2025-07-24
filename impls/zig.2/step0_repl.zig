const std = @import("std");
const Linenoise = @import("linenoize").Linenoise;

fn read(s: []const u8) []const u8 {
    return s;
}

fn eval(s: []const u8) []const u8 {
    return s;
}

fn print(s: []const u8) []const u8 {
    return s;
}

fn rep(s: []const u8) []const u8 {
    return print(eval(read(s)));
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    while (try ln.linenoise("user> ")) |input| {
        defer allocator.free(input);
        const res = rep(input);
        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}
