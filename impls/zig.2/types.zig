const std = @import("std");

pub const MalType = union(enum) {
    string: String,
    keyword: []const u8,
    symbol: []const u8,
    nil: void,
    int: i32,
    float: f32,
    list: std.ArrayListUnmanaged(MalType),
    vector: std.ArrayListUnmanaged(MalType),
    err: String,
    function: MalFn,
    builtin: *const fn (allocator: std.mem.Allocator, args: []MalType) MalType,

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

    pub const MalFn = struct {
        ast: *MalType,
        args: [][]const u8,
    };

    pub fn makeError(allocator: std.mem.Allocator, msg: []const u8) MalType {
        const err_msg = MalType.String.initFrom(allocator, msg) catch {
            return .{ .nil = undefined };
        };
        return .{ .err = err_msg };
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
            .function => try buffer.appendSlice("#<function>"),
            .builtin => try buffer.appendSlice("#<function><builtin>"),
        }
    }
};
