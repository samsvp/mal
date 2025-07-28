const std = @import("std");
const Linenoise = @import("linenoize").Linenoise;

const MalType = @import("types.zig").MalType;
const Reader = @import("reader.zig");
const Env = @import("env.zig").Env;

fn read(allocator: std.mem.Allocator, s: []const u8) !MalType {
    return try Reader.readStr(allocator, s);
}

fn print_eval(allocator: std.mem.Allocator, s: MalType) void {
    const str = s.toString(allocator) catch unreachable;
    defer allocator.free(str);

    std.debug.print("EVAL: {s}\n", .{str});
}

fn eval(allocator: std.mem.Allocator, s: *MalType, env: *Env) MalType {
    const is_eval = env.get("DEBUG-EVAL");
    if (is_eval) |flag| {
        switch (flag) {
            .nil, .err => {},
            .boolean => |f| if (f)
                print_eval(allocator, s.*),
            else => print_eval(allocator, s.*),
        }
    }
    return switch (s.*) {
        .symbol => |symbol| if (env.getPtr(symbol.getStr())) |value|
            value.clone(allocator)
        else
            MalType.makeErrorF(allocator, "Symbol {s} not found.", .{symbol.getStr()}),
        .list => |*list| {
            if (list.getItems().len == 0) {
                return s.clone(allocator);
            }

            switch (list.getItems()[0]) {
                .symbol => |symbol| {
                    const s_chars = symbol.getStr();
                    if (std.mem.eql(u8, s_chars, "let*")) {
                        const items = list.getItems();
                        if (items.len != 3) {
                            return MalType.makeError(allocator, "'let*' takes two parametes");
                        }
                        var new_env = Env.init_with_parent(env);
                        defer new_env.deinit(allocator);

                        const arr = switch (items[1]) {
                            .list, .vector => |arr| blk: {
                                if (arr.getItems().len % 2 != 0) {
                                    return MalType.makeError(allocator, "'let*' takes an even number of parameters.");
                                }
                                break :blk arr;
                            },
                            else => return MalType.makeError(allocator, "Second element of 'let*' must be a list or vector."),
                        };

                        const args_items = arr.getItems();
                        for (0..args_items.len / 2) |_i| {
                            const i = 2 * _i;

                            var arg_env = Env.init_with_parent(&new_env);
                            defer arg_env.deinit(allocator);

                            const key = args_items[i];

                            var value = eval(allocator, &args_items[i + 1], &arg_env);
                            defer value.deinit(allocator) catch {};

                            switch (key) {
                                .symbol => |new_symbol| {
                                    switch (value) {
                                        .err => return value.clone(allocator),
                                        else => {},
                                    }
                                    var ret = new_env.set(allocator, new_symbol.getStr(), &value);
                                    switch (ret) {
                                        .err => return ret.clone(allocator),
                                        else => {},
                                    }
                                },
                                else => return MalType.makeError(allocator, "'let*' key must be symbol."),
                            }
                        }

                        return eval(allocator, &items[2], &new_env);
                    }
                    if (std.mem.eql(u8, s_chars, "def!")) {
                        const items = list.getItems();
                        if (items.len != 3) {
                            return MalType.makeError(allocator, "'def!' takes two parametes");
                        }

                        switch (items[1]) {
                            .symbol => {},
                            else => return MalType.makeError(allocator, "Second parameter of 'def!' must be a symbol"),
                        }

                        var val = eval(allocator, &items[2], env);
                        defer val.deinit(allocator) catch {};
                        switch (val) {
                            .err => return val.clone(allocator),
                            else => {},
                        }
                        const ret = env.set(allocator, items[1].symbol.getStr(), &val);
                        switch (ret) {
                            .err => return ret,
                            else => {},
                        }
                        return val.clone(allocator);
                    }
                },
                else => {},
            }

            var new_list = MalType.Array.emptyList(allocator);
            switch (new_list) {
                .err => return new_list,
                else => {},
            }

            for (list.getItems()) |*arg| {
                const val = eval(allocator, arg, env);
                const ret = new_list.list.append(allocator, val);
                switch (ret) {
                    .err => {
                        new_list.deinit(allocator) catch {};
                        return ret;
                    },
                    else => {},
                }
            }

            const fst = new_list.list.getItems()[0];
            switch (fst) {
                .builtin => |op| {
                    defer new_list.deinit(allocator) catch {};
                    const ret = op(allocator, new_list.list.getItems()[1..]);
                    return ret;
                },
                .err => return fst,
                else => return new_list,
            }
        },
        .vector => |*v| {
            var new_v = MalType.Array.emptyVector(allocator);
            switch (new_v) {
                .err => return new_v,
                else => {},
            }
            for (v.getItems()) |*item| {
                const new_item = eval(allocator, item, env);
                const res = new_v.vector.append(allocator, new_item);
                switch (res) {
                    .err => {
                        new_v.deinit(allocator) catch {};
                        return res;
                    },
                    else => {},
                }
            }
            return new_v;
        },
        .dict => |dict| {
            var new_dict = MalType.Dict.init() catch {
                return MalType.makeError(allocator, "Could not create new dict, Out of Memory");
            };

            var iter = dict.getValues().iterator();
            while (iter.next()) |entry| {
                var value = eval(allocator, entry.value_ptr, env);
                defer value.deinit(allocator) catch {};

                const ret = new_dict.dict.add(allocator, entry.key_ptr, &value);
                switch (ret) {
                    .err => {
                        new_dict.deinit(allocator) catch {};
                        return ret;
                    },
                    else => {},
                }
            }
            return new_dict;
        },
        else => s.clone(allocator),
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
    defer val.deinit(allocator) catch {};

    var ret = eval(
        allocator,
        &val,
        env,
    );
    defer ret.deinit(allocator) catch {};
    return print(
        allocator,
        ret,
    );
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    var env = try Env.init_root(allocator);
    defer env.deinit(allocator);

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    ln.history.load("history.txt") catch {};
    defer ln.history.save("history.txt") catch |err| {
        std.debug.print("Failed to print history {any}\n", .{err});
    };

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
