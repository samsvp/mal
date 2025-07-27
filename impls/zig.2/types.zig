const std = @import("std");
const PageShared = @import("shared.zig").PageShared;

/// Enum holding all of our Lisp types.
pub const MalType = union(enum) {
    string: PageShared(String),
    keyword: PageShared(String),
    symbol: PageShared(String),
    nil,
    int: i32,
    float: f32,
    list: PageShared(std.ArrayListUnmanaged(MalType)),
    vector: PageShared(std.ArrayListUnmanaged(MalType)),
    err: PageShared(String),
    dict: PageShared(Dict),
    function: Fn,
    builtin: *const fn (allocator: std.mem.Allocator, args: []MalType) MalType,

    pub const Array = std.ArrayListUnmanaged(MalType);

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
                entry.key_ptr.deinit(allocator) catch {};
                entry.value_ptr.deinit(allocator) catch {};
            }
        }

        const Context = struct {
            pub fn hash(_: Context, value: MalType) u64 {
                var h: std.hash.Wyhash = .init(0);
                const b = switch (value) {
                    .int => |i| std.mem.asBytes(&i),
                    .string, .keyword => |s| s.get().getStr(),
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
        const err = PageShared(String).init(err_msg) catch {
            return .nil;
        };
        return .{ .err = err };
    }

    pub fn clone(self: *MalType) !MalType {
        return switch (self.*) {
            MalType.string, MalType.err, MalType.keyword, MalType.symbol => |*s| try s.clone(),
            MalType.list, MalType.vector => |*l| try l.clone(),
            MalType.dict => |*d| try d.clone(),
            else => return self,
        };
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
                .string => |s2| std.mem.eql(u8, s1.get().getStr(), s2.get().getStr()),
                else => false,
            },
            .err => |s1| switch (b) {
                .err => |s2| std.mem.eql(u8, s1.get().getStr(), s2.get().getStr()),
                else => false,
            },
            .symbol => |s1| switch (b) {
                .symbol => |s2| std.mem.eql(u8, s1.get().getStr(), s2.get().getStr()),
                else => false,
            },
            .keyword => |s1| switch (b) {
                .keyword => |s2| std.mem.eql(u8, s1.get().getStr(), s2.get().getStr()),
                else => false,
            },
            .list => |l1| switch (b) {
                .list => |l2| {
                    if (l1.get().items.len != l2.get().items.len) return false;
                    for (l1.get().items, l2.get().items) |v1, v2| {
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
                    if (l1.get().items.len != l2.get().items.len) return false;
                    for (l1.get().items, l2.get().items) |v1, v2| {
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
                    if (d1.get().values.size != d2.get().values.size) return false;
                    var iter = d1.get().values.iterator();
                    while (iter.next()) |entry| {
                        if (d2.get().values.get(entry.key_ptr.*)) |val| {
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
            .function, .builtin => false,
        };
    }

    pub fn toString(self: MalType, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        try self.toStringInternal(&buffer);
        return try buffer.toOwnedSlice();
    }

    fn toStringInternal(self: MalType, buffer: *std.ArrayList(u8)) !void {
        switch (self) {
            .symbol, .keyword => |s| try buffer.appendSlice(s.get().getStr()),
            .string => |s| try std.fmt.format(buffer.writer(), "\"{s}\"", .{s.get().getStr()}),
            .err => |s| try std.fmt.format(buffer.writer(), "ERROR: {s}", .{s.get().getStr()}),
            .nil => try buffer.appendSlice("nil"),
            .int => |i| try std.fmt.format(buffer.writer(), "{}", .{i}),
            .float => |f| try std.fmt.format(buffer.writer(), "{}", .{f}),
            .list => |l| {
                try buffer.appendSlice("(");
                for (l.get().items, 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice(")");
            },
            .vector => |a| {
                try buffer.appendSlice("[");
                for (a.get().items, 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice("]");
            },
            .dict => |d| {
                try buffer.appendSlice("{");
                var iter = d.get().values.iterator();
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

    pub fn deinit(self: *MalType, allocator: std.mem.Allocator) !void {
        switch (self.*) {
            // It would actually be way better if all of the data of a list were stored sequentially, without the need
            // of a for loop. I would need to rewrite the whole structure of the data though. This is something to keep in
            // mind, though.
            MalType.list, MalType.vector => |*list| {
                for (list.get().items) |*item| {
                    try item.deinit(allocator);
                }
                try list.deinit(allocator);
            },
            MalType.dict => |*d| {
                try d.deinit(allocator);
            },
            MalType.string, MalType.err, MalType.keyword, MalType.symbol => |*s| {
                try s.deinit(allocator);
            },
            else => return,
        }
    }
};
