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

fn eval(allocator: std.mem.Allocator, og_s: *MalType, og_env: *Env) MalType {
    const swapS = struct {
        pub fn swap(a: std.mem.Allocator, s1: *MalType, s2: *MalType) void {
            const s = s2.clone(a);
            s1.deinit(a) catch unreachable;
            s1.* = s;
        }
    }.swap;

    var env = og_env.clone();
    defer env.deinit(allocator);

    var s = og_s.clone(allocator);
    defer s.deinit(allocator) catch unreachable;

    while (true) {
        const is_eval = env.get("DEBUG-EVAL");
        if (is_eval) |flag| {
            switch (flag) {
                .nil, .err => {},
                .boolean => |f| if (f)
                    print_eval(allocator, s),
                else => print_eval(allocator, s),
            }
        }

        return switch (s) {
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
                        if (std.mem.eql(u8, s_chars, "swap!")) {
                            const items = list.getItems();
                            if (items.len < 3) {
                                return MalType.makeError(allocator, "'swap!' takes at least two parameters");
                            }

                            var fst = eval(allocator, &items[1], env);
                            defer fst.deinit(allocator) catch unreachable;

                            var atom = switch (fst) {
                                .atom => |a| a,
                                else => return MalType.makeError(allocator, "First argument must be an atom"),
                            };

                            var snd = eval(allocator, &items[2], env);
                            defer snd.deinit(allocator) catch unreachable;

                            switch (snd) {
                                .function, .builtin => {},
                                else => return MalType.makeError(allocator, "Second parameter must be function"),
                            }

                            var arr = [_]MalType{ snd, atom.get() };
                            var new_arr = MalType.Array.initList(allocator, &arr) catch
                                return MalType.makeError(allocator, "Could not initialize new list, OOM");
                            defer new_arr.deinit(allocator) catch unreachable;

                            _ = new_arr.list.addMutSlice(allocator, items[3..]);

                            var res = eval(allocator, &new_arr, env);
                            return atom.reset(allocator, &res);
                        }
                        if (std.mem.eql(u8, s_chars, "eval")) {
                            const items = list.getItems();
                            if (items.len != 2) {
                                return MalType.makeError(allocator, "'eval' takes one parameter");
                            }

                            var expr = eval(allocator, &items[1], env);
                            defer expr.deinit(allocator) catch unreachable;

                            var res = eval(allocator, &expr, env.getRoot());
                            swapS(allocator, &s, &res);
                            continue;
                        }
                        if (std.mem.eql(u8, s_chars, "let*")) {
                            const items = list.getItems();
                            if (items.len != 3) {
                                return MalType.makeError(allocator, "'let*' takes two parameters");
                            }
                            var new_env = Env.initWithParent(allocator, env);
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

                                var arg_env = Env.initWithParent(allocator, new_env);
                                defer arg_env.deinit(allocator);

                                const key = args_items[i];

                                var value = eval(allocator, &args_items[i + 1], arg_env);
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

                            swapS(allocator, &s, &items[2]);
                            env.deinit(allocator);
                            env = new_env.clone();
                            continue;
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
                            const ret = env.getRoot().set(allocator, items[1].symbol.getStr(), &val);
                            switch (ret) {
                                .err => return ret,
                                else => {},
                            }
                            return val.clone(allocator);
                        }
                        if (std.mem.eql(u8, s_chars, "do")) {
                            const items = list.getItems();
                            if (items.len == 1) {
                                return .nil;
                            }

                            var res: MalType = .nil;
                            for (items[1 .. items.len - 1]) |*item| {
                                var res_eval = eval(allocator, item, env);
                                defer res_eval.deinit(allocator) catch {};

                                res.deinit(allocator) catch {};
                                switch (res_eval) {
                                    .err => return res_eval.clone(allocator),
                                    else => res = res_eval.clone(allocator),
                                }
                            }
                            swapS(allocator, &s, &items[items.len - 1]);
                            continue;
                        }
                        if (std.mem.eql(u8, s_chars, "if")) {
                            const items = list.getItems();
                            if (items.len != 3 and items.len != 4) {
                                return MalType.makeError(allocator, "'if' takes only 1 or 2 parameters");
                            }

                            var cond = eval(allocator, &items[1], env);
                            defer cond.deinit(allocator) catch unreachable;
                            switch (cond) {
                                .err => return cond.clone(allocator),
                                .nil => if (items.len == 3) return .nil else swapS(allocator, &s, &items[3]),
                                .boolean => |b| if (b)
                                    swapS(allocator, &s, &items[2])
                                else if (items.len == 3)
                                    return .nil
                                else
                                    swapS(allocator, &s, &items[3]),

                                else => swapS(allocator, &s, &items[2]),
                            }
                            continue;
                        }
                        if (std.mem.eql(u8, s_chars, "fn*")) {
                            const items = list.getItems();
                            if (items.len != 3) {
                                return MalType.makeError(allocator, "'fn*' takes only 2 parameters, function arguments and body.");
                            }

                            const args = switch (items[1]) {
                                .vector, .list => |arr| arr.getItems(),
                                else => return MalType.makeError(allocator, "'fn*' arguments must be inside a list"),
                            };

                            const ast = &items[2];
                            return MalType.Fn.init(allocator, ast, args, env);
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
                    var val = eval(allocator, arg, env);
                    const ret = new_list.list.append(allocator, val);
                    switch (ret) {
                        .err => {
                            val.deinit(allocator) catch unreachable;
                            new_list.deinit(allocator) catch unreachable;
                            return ret;
                        },
                        else => {},
                    }
                }

                var fst = new_list.list.getItems()[0];
                switch (fst) {
                    .builtin => |op| {
                        defer new_list.deinit(allocator) catch {};
                        const ret = op(allocator, new_list.list.getItems()[1..]);
                        return ret;
                    },
                    .function => |*f| {
                        defer new_list.deinit(allocator) catch {};

                        const fn_args = f.getArgs();
                        var ast = f.getAst().clone(allocator);
                        defer ast.deinit(allocator) catch unreachable;

                        if (fn_args.len == 0) {
                            swapS(allocator, &s, &ast);
                            env.deinit(allocator);
                            env = f.getEnv();
                            continue;
                        }

                        const args = new_list.list.getItems()[1..];
                        if (args.len == 0) {
                            return fst.clone(allocator);
                        }

                        if (args.len != fn_args.len) {
                            return MalType.makeErrorF(
                                allocator,
                                "Wrong number of arguments: expected {d}, got {d}",
                                .{ fn_args.len, args.len },
                            );
                        }

                        var fn_env = Env.initWithParent(allocator, f.getEnv());
                        defer fn_env.deinit(allocator);

                        for (fn_args, args) |arg_name, *arg_value| {
                            const ret = fn_env.set(allocator, arg_name, arg_value);
                            switch (ret) {
                                .err => return ret,
                                else => {},
                            }
                        }

                        swapS(allocator, &s, &ast);
                        env.deinit(allocator);
                        env = fn_env.clone();
                        continue;
                    },
                    .err => {
                        defer new_list.deinit(allocator) catch unreachable;
                        return fst.clone(allocator);
                    },
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
                var new_dict = MalType.Dict.init(allocator) catch {
                    return MalType.makeError(allocator, "Could not create new dict, Out of Memory");
                };

                var iter = dict.getValues().iterator();
                while (iter.next()) |entry| {
                    var key_value = eval(allocator, entry.key_ptr, env);
                    defer key_value.deinit(allocator) catch unreachable;

                    var value = eval(allocator, entry.value_ptr, env);
                    defer value.deinit(allocator) catch unreachable;

                    const ret = new_dict.dict.add(allocator, &key_value, &value);
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
}

fn print(allocator: std.mem.Allocator, s: MalType) []const u8 {
    return s.toString(allocator) catch "Could not build string.";
}

fn re(allocator: std.mem.Allocator, s: []const u8, env: *Env) !MalType {
    var val = try read(
        allocator,
        s,
    );
    defer val.deinit(allocator) catch {};

    return eval(
        allocator,
        &val,
        env,
    );
}

fn rep(allocator: std.mem.Allocator, s: []const u8, env: *Env) ![]const u8 {
    var ret = try re(allocator, s, env);
    defer ret.deinit(allocator) catch unreachable;

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

    var env = try Env.initRoot(allocator);
    defer env.deinitForce(allocator);

    const load_file =
        \\(def! load-file (fn* (f) (eval (read-string (str "(do " (slurp f) " nil)")))))
    ;
    allocator.free(try rep(allocator, load_file, env));

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    ln.history.load("history.txt") catch {};
    defer ln.history.save("history.txt") catch |err| {
        std.debug.print("Failed to print history {any}\n", .{err});
    };

    while (try ln.linenoise("user> ")) |input| {
        defer allocator.free(input);
        const res = rep(allocator, input, env) catch |err| {
            try stdout.print("{any}\n", .{err});
            continue;
        };
        defer allocator.free(res);

        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}
