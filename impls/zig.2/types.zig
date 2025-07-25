const std = @import("std");

pub const MalType = union(enum) {
    string: []const u8,
    keyword: []const u8,
    symbol: []const u8,
    nil: void,
    int: i32,
    float: f32,
    list: std.ArrayListUnmanaged(MalType),
    vector: std.ArrayListUnmanaged(MalType),

    pub fn toString(self: MalType, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        try self.toStringInternal(&buffer);
        return try buffer.toOwnedSlice();
    }

    fn toStringInternal(self: MalType, buffer: *std.ArrayList(u8)) !void {
        switch (self) {
            .symbol, .keyword => |s| try buffer.appendSlice(s),
            .string => |s| try std.fmt.format(buffer.writer(), "\"{s}\"", .{s}),
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
        }
    }
};
