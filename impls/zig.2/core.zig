const std = @import("std");
const reader = @import("reader.zig");
const printer = @import("printer.zig");
const MalType = @import("types.zig").MalType;

pub fn eql(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len < 2) {
        return MalType.makeError(allocator, "accepts at least two parameters.");
    }

    return for (args[1..]) |a| {
        if (!args[0].eql(a)) break .{ .boolean = false };
    } else blk: {
        break :blk .{ .boolean = true };
    };
}

pub fn notEql(allocator: std.mem.Allocator, args: []MalType) MalType {
    const ret = eql(allocator, args);
    return switch (ret) {
        .boolean => |b| .{ .boolean = !b },
        else => ret,
    };
}

pub fn cmp(allocator: std.mem.Allocator, args: []MalType, cmpFn: fn (f32, f32) bool) MalType {
    if (args.len < 2) {
        return MalType.makeError(allocator, "accepts at least two parameters.");
    }

    const v1: f32 = switch (args[0]) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => return MalType.makeError(allocator, "Can only compare numeric types"),
    };

    return for (args[1..]) |a| {
        const v2: f32 = switch (a) {
            .int => |i| @floatFromInt(i),
            .float => |f| f,
            else => break MalType.makeError(allocator, "Can only compare numeric types"),
        };
        if (!cmpFn(v1, v2)) break .{ .boolean = false };
    } else blk: {
        break :blk .{ .boolean = true };
    };
}

pub fn less(allocator: std.mem.Allocator, args: []MalType) MalType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 < v2;
        }
    }.f;
    return cmp(allocator, args, lessFn);
}

pub fn lessEql(allocator: std.mem.Allocator, args: []MalType) MalType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 <= v2;
        }
    }.f;
    return cmp(allocator, args, lessFn);
}

pub fn bigger(allocator: std.mem.Allocator, args: []MalType) MalType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 > v2;
        }
    }.f;
    return cmp(allocator, args, lessFn);
}

pub fn biggerEql(allocator: std.mem.Allocator, args: []MalType) MalType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 >= v2;
        }
    }.f;
    return cmp(allocator, args, lessFn);
}

pub fn add(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        // TODO! return a function that does the sum, so it can be used in map, etc
        return MalType.makeError(allocator, "Must give at least one argument to '+'");
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value| {
                switch (value) {
                    .int => |i_val| acc += i_val,
                    else => return MalType.makeError(allocator, "Can only add int to other ints"),
                }
            }
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value| {
                switch (value) {
                    .float => |f_val| acc += f_val,
                    .int => |i_val| acc += @floatFromInt(i_val),
                    else => return MalType.makeError(allocator, "Can only add float to other floats"),
                }
            }
            return .{ .float = acc };
        },
        .string => {
            var acc = MalType.String.initFrom(allocator, "") catch return MalType.makeError(allocator, "Could not init string");
            for (args) |arg| {
                switch (arg) {
                    .string => |s| {
                        acc.string.addMut(allocator, s) catch {
                            acc.deinit(allocator) catch {};
                            return MalType.makeError(allocator, "Could not add strings, OOM");
                        };
                    },
                    else => {
                        acc.deinit(allocator) catch {};
                        return MalType.makeError(allocator, "Can only add string to other strings");
                    },
                }
            }
            return acc;
        },
        .list, .vector => |*arr| {
            var acc = arr.clone(allocator) catch {
                return MalType.makeError(allocator, "Could not create new array");
            };
            for (args[1..]) |*arg| {
                switch (arg.*) {
                    .list, .vector => |*vs| {
                        const ret = switch (acc) {
                            .list => |*l| l.addMut(allocator, vs),
                            .vector => |*v| v.addMut(allocator, vs),
                            else => unreachable,
                        };
                        switch (ret) {
                            .err => return ret,
                            else => {},
                        }
                    },
                    else => {
                        acc.deinit(allocator) catch {};
                        return MalType.makeError(allocator, "Can only add string to other strings");
                    },
                }
            }
            return acc;
        },
        else => return MalType.makeError(allocator, "Can not add type"),
    }
}

pub fn sub(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        // TODO! return a function that does the sum, so it can be used in map, etc
        return MalType.makeError(allocator, "Must give at least one argument to '-'");
    }

    if (args.len == 1) {
        return switch (args[0]) {
            .int => |i| .{ .int = -i },
            .float => |f| .{ .float = -f },
            else => MalType.makeError(allocator, "Can not negate type"),
        };
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value| {
                switch (value) {
                    .int => |i_val| acc -= i_val,
                    else => return MalType.makeError(allocator, "Can only subtract int to other ints"),
                }
            }
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value| {
                switch (value) {
                    .float => |f_val| acc -= f_val,
                    .int => |i_val| acc -= @floatFromInt(i_val),
                    else => return MalType.makeError(allocator, "Can only subtract float to other floats"),
                }
            }
            return .{ .float = acc };
        },
        else => return MalType.makeError(allocator, "Can not subtract type"),
    }
}

pub fn mul(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        // TODO! return a function that does the sum, so it can be used in map, etc
        return MalType.makeError(allocator, "Must give at least one argument to '*'");
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value| {
                switch (value) {
                    .int => |i_val| acc *= i_val,
                    else => return MalType.makeError(allocator, "Can only multiply int to other ints"),
                }
            }
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value| {
                switch (value) {
                    .float => |f_val| acc *= f_val,
                    .int => |i_val| acc *= @floatFromInt(i_val),
                    else => return MalType.makeError(allocator, "Can only multiply float to other floats"),
                }
            }
            return .{ .float = acc };
        },
        else => return MalType.makeError(allocator, "Can not multiply type"),
    }
}

pub fn div(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        // TODO! return a function that does the sum, so it can be used in map, etc
        return MalType.makeError(allocator, "Must give at least one argument to '/'");
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value| {
                switch (value) {
                    .int => |i_val| {
                        if (i_val != 0) {
                            acc = @divFloor(acc, i_val);
                        } else {
                            return MalType.makeError(allocator, "Division by zero");
                        }
                    },
                    else => return MalType.makeError(allocator, "Can only divide int to other ints"),
                }
            }
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value| {
                var v: f32 = 0;
                switch (value) {
                    .float => |f_val| v = f_val,
                    .int => |i_val| v = @floatFromInt(i_val),
                    else => return MalType.makeError(allocator, "Can only divide float to other floats"),
                }
                if (v != 0) {
                    acc /= v;
                } else {
                    return MalType.makeError(allocator, "Division by zero");
                }
            }
            return .{ .float = acc };
        },
        else => return MalType.makeError(allocator, "Can not divide type"),
    }
}

pub fn list(allocator: std.mem.Allocator, args: []MalType) MalType {
    return MalType.Array.initList(allocator, args) catch MalType.makeError(allocator, "Could not create list.");
}

pub fn listQuestion(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        return .{ .boolean = false };
    }

    if (args.len > 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    return switch (args[0]) {
        .list => .{ .boolean = true },
        else => .{ .boolean = false },
    };
}

pub fn emptyQuestion(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        return .{ .boolean = true };
    }

    if (args.len > 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    return switch (args[0]) {
        .list, .vector => |arr| if (arr.getItems().len == 0) .{ .boolean = true } else .{ .boolean = false },
        .dict => |d| if (d.getValues().size == 0) .{ .boolean = true } else .{ .boolean = false },
        else => .{ .boolean = false },
    };
}

pub fn count(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        return .{ .int = 0 };
    }

    if (args.len > 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    return switch (args[0]) {
        .list, .vector => |arr| .{ .int = @intCast(arr.getItems().len) },
        .dict => |d| .{ .int = @intCast(d.getValues().size) },
        else => .{ .int = 0 },
    };
}

pub fn str(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len == 0) {
        return MalType.String.initFrom(allocator, "") catch unreachable;
    }

    var acc = MalType.String.initFrom(allocator, "") catch return MalType.makeError(allocator, "Could not init string");
    for (args) |arg| {
        const s = switch (arg) {
            .string => |s| s.getStr(),
            else => arg.toString(allocator) catch unreachable,
        };
        acc.string.addChars(allocator, s) catch {
            acc.deinit(allocator) catch unreachable;
            return MalType.makeError(allocator, "Could not add strings, OOM");
        };
    }
    return acc;
}

pub fn prn(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    printer.prStr(allocator, args[0], true);
    return .nil;
}

pub fn readString(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    return switch (args[0]) {
        .string => |s| reader.readStr(allocator, s.getStr()) catch |err|
            MalType.makeErrorF(allocator, "Error reading string: {any}", .{err}),
        else => MalType.makeError(allocator, "Argument must be string."),
    };
}

pub fn slurp(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    const path = switch (args[0]) {
        .string => |s| s.getStr(),
        else => return MalType.makeError(allocator, "Argument must be string."),
    };

    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return MalType.makeErrorF(allocator, "Could not read file: {any}.", .{err});
    };
    defer file.close();

    const file_size = file.getEndPos() catch |err| {
        return MalType.makeErrorF(allocator, "Erro reading file: {any}.", .{err});
    };
    const buffer = allocator.alloc(u8, file_size) catch unreachable;
    defer allocator.free(buffer);

    _ = file.readAll(buffer) catch |err| {
        return MalType.makeErrorF(allocator, "Erro reading file: {any}.", .{err});
    };
    return MalType.String.initFrom(allocator, buffer) catch |err| MalType.makeErrorF(
        allocator,
        "Could not convert file to string: {any}",
        .{err},
    );
}

pub fn atom(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    return MalType.Atom.init(allocator, args[0]);
}

pub fn atomQuestion(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    return switch (args[0]) {
        .atom => .{ .boolean = true },
        else => .{ .boolean = false },
    };
}

pub fn deref(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 1) {
        return MalType.makeError(allocator, "Only accepts one argument");
    }

    return switch (args[0]) {
        .atom => |a| a.get(),
        else => MalType.makeError(allocator, "Type error: Deref only works on atoms."),
    };
}

pub fn resetBang(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 2) {
        return MalType.makeError(allocator, "Only accepts two arguments");
    }

    var a = switch (args[0]) {
        .atom => |a| a,
        else => return MalType.makeError(allocator, "Type error: Deref only works on atoms."),
    };
    var val = args[1];
    return switch (val) {
        .err => val.clone(allocator),
        else => a.reset(allocator, &val),
    };
}
