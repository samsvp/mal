const std = @import("std");

const MalType = @import("types.zig").MalType;

/// Represents a MAL environment (i.e. a scope).
pub const Env = struct {
    mapping: std.StringHashMapUnmanaged(MalType),
    parent: ?*Env,

    pub fn init() Env {
        return .{
            .mapping = .empty,
            .parent = null,
        };
    }

    pub fn init_with_parent(env: *Env) Env {
        return .{
            .mapping = .empty,
            .parent = env,
        };
    }

    /// Creates a new root environment, with the default functions.
    pub fn init_root(allocator: std.mem.Allocator) !Env {
        var env = Env.init();
        try env.mapping.put(allocator, "+", .{ .builtin = add });
        try env.mapping.put(allocator, "-", .{ .builtin = sub });
        try env.mapping.put(allocator, "*", .{ .builtin = mul });
        try env.mapping.put(allocator, "/", .{ .builtin = div });
        return env;
    }

    pub fn get(self: Env, key: []const u8) ?MalType {
        return self.mapping.get(key);
    }

    pub fn add_val(
        self: *Env,
        allocator: std.mem.Allocator,
        key: []const u8,
        value: MalType,
    ) !void {
        try self.mapping.put(allocator, key, value);
    }

    pub fn deinit(self: *Env, allocator: std.mem.Allocator) void {
        // !TODO!: deallocate variables
        self.mapping.deinit(allocator);
    }
};

fn add(allocator: std.mem.Allocator, args: []MalType) MalType {
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
                        acc.addMut(allocator, s) catch {
                            acc.deinit(allocator);
                            return MalType.makeError(allocator, "Could not add strings, OOM");
                        };
                    },
                    else => {
                        acc.deinit(allocator);
                        return MalType.makeError(allocator, "Can only add string to other strings");
                    },
                }
            }
            return .{ .string = acc };
        },
        else => return MalType.makeError(allocator, "Can not add type"),
    }
}

fn sub(allocator: std.mem.Allocator, args: []MalType) MalType {
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

fn mul(allocator: std.mem.Allocator, args: []MalType) MalType {
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

fn div(allocator: std.mem.Allocator, args: []MalType) MalType {
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
