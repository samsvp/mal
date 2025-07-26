const std = @import("std");

/// Enum holding all of our Lisp types.
pub const MalType = union(enum) {
    string: String,
    keyword: []const u8,
    symbol: []const u8,
    nil,
    int: i32,
    float: f32,
    list: std.ArrayListUnmanaged(MalType),
    vector: std.ArrayListUnmanaged(MalType),
    err: String,
    dict: Dict,
    function: Fn,
    builtin: *const fn (allocator: std.mem.Allocator, args: []MalType) MalType,

    /// A basic string type which is basically a wrapper with helper functions to concatenate string and handle its memory.
    pub const String = struct {
        chars: std.ArrayListUnmanaged(u8),

        pub fn initFrom(allocator: std.mem.Allocator, str: []const u8) !String {
            var chars = try std.ArrayListUnmanaged(u8).initCapacity(allocator, str.len);
            chars.appendSliceAssumeCapacity(str);
            return .{ .chars = chars };
        }

        pub fn getStr(self: String) []const u8 {
            return self.chars.items;
        }

        /// Concatenates s1 and s2 on a new string
        pub fn add(allocator: std.mem.Allocator, s1: String, s2: String) !String {
            var chars = try std.ArrayListUnmanaged(u8).initCapacity(allocator, s1.chars.items.len + s2.chars.items.len);
            chars.appendSliceAssumeCapacity(s1.getStr());
            chars.appendSliceAssumeCapacity(s2.getStr());
            return .{ .chars = chars };
        }

        /// Add s to self
        pub fn addMut(self: *String, allocator: std.mem.Allocator, s: String) !void {
            try self.chars.appendSlice(allocator, s.getStr());
        }

        pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
            self.chars.deinit(allocator);
        }
    };

    /// A basic type to define user made functions
    pub const Fn = struct {
        ast: *MalType,
        args: [][]const u8,
    };

    pub const Dict = struct {
        values: std.HashMapUnmanaged(MalType, MalType, Context, std.hash_map.default_max_load_percentage),

        pub fn add(self: *Dict, allocator: std.mem.Allocator, key: MalType, value: MalType) MalType {
            switch (key) {
                .int, .string, .keyword => {
                    self.values.put(allocator, key, value) catch {
                        return makeError(allocator, "Allocator error: Could not add value to hash map");
                    };
                    return .nil;
                },
                else => return makeError(allocator, "Unhashable key type"),
            }
        }

        pub fn init() Dict {
            const values: std.HashMapUnmanaged(MalType, MalType, Context, std.hash_map.default_max_load_percentage) = .empty;
            return .{ .values = values };
        }

        pub fn deinit(self: *Dict, allocator: std.mem.Allocator) void {
            defer self.values.deinit(allocator);
            var iter = self.values.iterator();
            while (iter.next()) |entry| {
                entry.key_ptr.deinit(allocator);
                entry.value_ptr.deinit(allocator);
            }
        }

        const Context = struct {
            pub fn hash(_: Context, value: MalType) u64 {
                var h: std.hash.Wyhash = .init(0);
                const b = switch (value) {
                    .int => |i| std.mem.asBytes(&i),
                    .string => |s| s.getStr(),
                    .keyword => |s| s,
                    else => "0",
                };
                h.update(b);
                return h.final();
            }

            pub fn eql(_: Context, a: MalType, b: MalType) bool {
                return a.eql(b);
            }
        };
    };

    pub fn makeError(allocator: std.mem.Allocator, msg: []const u8) MalType {
        const err_msg = MalType.String.initFrom(allocator, msg) catch {
            return .nil;
        };
        return .{ .err = err_msg };
    }

    pub fn clone(self: MalType, allocator: std.mem.Allocator) MalType {
        switch (self) {
            .string => |s| {
                const new_s = String.initFrom(allocator, s.getStr()) catch {
                    return makeError(allocator, "Could not create string, OOM");
                };
                return .{ .string = new_s };
            },
            .err => |s| {
                const new_s = String.initFrom(allocator, s.getStr()) catch {
                    return makeError(allocator, "Could not create string, OOM");
                };
                return .{ .err = new_s };
            },
            .keyword => |s| {
                const new_k = std.mem.Allocator.dupe(allocator, u8, s) catch {
                    return makeError(allocator, "Could not create string, OOM");
                };
                return .{ .keyword = new_k };
            },
            .symbol => |s| {
                const new_s = std.mem.Allocator.dupe(allocator, u8, s) catch {
                    return makeError(allocator, "Could not create string, OOM");
                };
                return .{ .symbol = new_s };
            },
            .list => |list| {
                var new_list: std.ArrayListUnmanaged(MalType) = .empty;
                for (list.items) |item| {
                    const new_item = item.clone(allocator);
                    new_list.append(allocator, new_item) catch unreachable;
                }
                return .{ .list = new_list };
            },
            .vector => |vector| {
                var vector_list: std.ArrayListUnmanaged(MalType) = .empty;
                for (vector.items) |item| {
                    const new_item = item.clone(allocator);
                    vector_list.append(allocator, new_item) catch unreachable;
                }
                return .{ .vector = vector_list };
            },
            .dict => |dict| {
                var new_dict = Dict.init();
                var iter = dict.values.iterator();
                while (iter.next()) |entry| {
                    _ = new_dict.add(allocator, entry.key_ptr.clone(allocator), entry.value_ptr.clone(allocator));
                }
                return .{ .dict = new_dict };
            },
            else => return self,
        }
    }

    pub fn eql(a: MalType, b: MalType) bool {
        return switch (a) {
            .int => |v1| switch (b) {
                .int => |v2| v1 == v2,
                else => false,
            },
            .float => |v1| switch (b) {
                .float => |v2| v1 == v2,
                else => false,
            },
            .string => |s1| switch (b) {
                .string => |s2| std.mem.eql(u8, s1.getStr(), s2.getStr()),
                else => false,
            },
            .err => |s1| switch (b) {
                .err => |s2| std.mem.eql(u8, s1.getStr(), s2.getStr()),
                else => false,
            },
            .keyword => |s1| switch (b) {
                .keyword => |s2| std.mem.eql(u8, s1, s2),
                else => false,
            },
            .list => |l1| switch (b) {
                .list => |l2| {
                    if (l1.items.len != l2.items.len) return false;
                    for (l1.items, l2.items) |v1, v2| {
                        if (!v1.eql(v2)) {
                            return false;
                        }
                    }
                    return true;
                },
                else => false,
            },
            .vector => |l1| switch (b) {
                .vector => |l2| {
                    if (l1.items.len != l2.items.len) return false;
                    for (l1.items, l2.items) |v1, v2| {
                        if (!v1.eql(v2)) {
                            return false;
                        }
                    }
                    return true;
                },
                else => false,
            },
            .dict => |d1| switch (b) {
                .dict => |d2| {
                    if (d1.values.size != d2.values.size) return false;
                    var iter = d1.values.iterator();
                    while (iter.next()) |entry| {
                        if (d2.values.get(entry.key_ptr.*)) |val| {
                            if (!val.eql(entry.value_ptr.*)) return false;
                        } else return false;
                    }
                    return true;
                },
                else => false,
            },
            .nil => switch (b) {
                .nil => true,
                else => false,
            },
            .function, .builtin, .symbol => false,
        };
    }

    pub fn toString(self: MalType, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        try self.toStringInternal(&buffer);
        return try buffer.toOwnedSlice();
    }

    fn toStringInternal(self: MalType, buffer: *std.ArrayList(u8)) !void {
        switch (self) {
            .symbol, .keyword => |s| try buffer.appendSlice(s),
            .string => |s| try std.fmt.format(buffer.writer(), "\"{s}\"", .{s.getStr()}),
            .err => |s| try std.fmt.format(buffer.writer(), "ERROR: {s}", .{s.getStr()}),
            .nil => try buffer.appendSlice("nil"),
            .int => |i| try std.fmt.format(buffer.writer(), "{}", .{i}),
            .float => |f| try std.fmt.format(buffer.writer(), "{}", .{f}),
            .list => |l| {
                try buffer.appendSlice("(");
                for (l.items, 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice(")");
            },
            .vector => |a| {
                try buffer.appendSlice("[");
                for (a.items, 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice("]");
            },
            .dict => |d| {
                try buffer.appendSlice("{");
                var iter = d.values.iterator();
                while (iter.next()) |entry| {
                    try entry.key_ptr.toStringInternal(buffer);
                    try buffer.appendSlice(" ");
                    try entry.value_ptr.toStringInternal(buffer);
                }
                try buffer.appendSlice("}");
            },
            .function => try buffer.appendSlice("#<function>"),
            .builtin => try buffer.appendSlice("#<function><builtin>"),
        }
    }

    pub fn deinit(self: *MalType, allocator: std.mem.Allocator) void {
        switch (self.*) {
            // It would actually be way better if all of the data of a list were stored sequentially, without the need
            // of a for loop. I would need to rewrite the whole structure of the data though. This is something to keep in
            // mind, though.
            MalType.list, MalType.vector => |*list| {
                defer list.deinit(allocator);
                for (list.items) |*item| {
                    item.deinit(allocator);
                }
            },
            MalType.dict => |*d| {
                d.deinit(allocator);
            },
            MalType.string, MalType.err => |*s| {
                s.deinit(allocator);
            },
            MalType.keyword, MalType.symbol => |s| {
                allocator.free(s);
            },
            else => return,
        }
    }
};
