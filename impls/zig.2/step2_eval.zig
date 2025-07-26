const std = @import("std");
const Linenoise = @import("linenoize").Linenoise;

const MalType = @import("types.zig").MalType;
const Reader = @import("reader.zig");
const Env = @import("env.zig").Env;

fn read(allocator: std.mem.Allocator, s: []const u8) !MalType {
    return try Reader.readStr(allocator, s);
}

fn eval(allocator: std.mem.Allocator, s: MalType, env: *Env) MalType {
    return switch (s) {
        .symbol => |symbol| {
            return if (env.get(symbol)) |value|
                value
            else else_blk: {
                const err = MalType.String.initFrom(allocator, "Symbol not found") catch unreachable;
                break :else_blk .{ .err = err };
            };
        },
        .list => |list| {
            if (list.items.len == 0) {
                return s;
            }

            var args: std.ArrayListUnmanaged(MalType) = .empty;
            for (list.items) |arg| {
                const val = eval(allocator, arg, env);
                args.append(allocator, val) catch unreachable;
            }

            const fst = args.items[0];
            switch (fst) {
                .builtin => |op| {
                    defer args.deinit(allocator);
                    const ret = op(allocator, args.items[1..]);
                    return ret;
                },
                else => return .{ .list = args },
            }
        },
        .vector => |vector| {
            var vec: std.ArrayListUnmanaged(MalType) = .empty;
            for (vector.items) |arg| {
                const val = eval(allocator, arg, env);
                vec.append(allocator, val) catch unreachable;
            }
            return .{ .vector = vec };
        },
        else => s,
    };
}

fn print(allocator: std.mem.Allocator, s: MalType) []const u8 {
    return s.toString(allocator) catch "Could not build string.";
}

fn rep(allocator: std.mem.Allocator, s: []const u8, env: *Env) ![]const u8 {
    var val = try read(
        allocator,
        s,
    );
    defer val.deinit(allocator);

    var t = eval(allocator, val, env);
    defer t.deinit(allocator);

    return print(allocator, t);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    ln.history.load("history.txt") catch {};
    defer ln.history.save("history.txt") catch |err| {
        std.debug.print("Failed to print history {any}\n", .{err});
    };

    var env = try Env.init_root(allocator);
    defer env.deinit(allocator);

    while (try ln.linenoise("user> ")) |input| {
        defer allocator.free(input);
        const res = rep(allocator, input, &env) catch |err| {
            try stdout.print("{any}\n", .{err});
            continue;
        };
        defer allocator.free(res);

        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}
