const std = @import("std");
const MalType = @import("types.zig").MalType;

pub fn eql(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 2) {
        return MalType.makeError(allocator, "accepts two parameters.");
    }

    return .{ .boolean = args[0].eql(args[1]) };
}

pub fn notEql(allocator: std.mem.Allocator, args: []MalType) MalType {
    if (args.len != 2) {
        return MalType.makeError(allocator, "accepts two parameters.");
    }

    return .{ .boolean = !args[0].eql(args[1]) };
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
        else => MalType.makeError(allocator, "Parameter must be list, array or dictionary."),
    };
}
