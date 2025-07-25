const std = @import("std");

pub const MalType = union(enum) {
    string: []const u8,
    keyword: []const u8,
    symbol: []const u8,
    nil: void,
    int: i32,
    float: f32,
    list: std.ArrayListUnmanaged(MalType),
    array: std.ArrayListUnmanaged(MalType),

    pub fn toString(self: MalType) []const u8 {
        return switch (self) {
            inline .symbol, .keyword, .string => |s| s,
            .nil => "nil",
            .list => |l| lst_blk: {
                std.debug.print("Length {d}\n", .{l.items.len});
                break :lst_blk "I'm a list";
            },
            else => "Not implemented",
        };
    }
};
