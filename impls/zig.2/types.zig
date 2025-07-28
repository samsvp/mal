const std = @import("std");
const Env = @import("env.zig").Env;
const Shared = @import("shared.zig");
const PageShared = Shared.PageShared;
const SharedError = Shared.SharedErrors;

/// Enum holding all of our Lisp types.
pub const MalType = union(enum) {
    string: String,
    keyword: String,
    symbol: String,
    nil,
    int: i32,
    float: f32,
    boolean: bool,
    list: Array,
    vector: Array,
    err: String,
    dict: Dict,
    function: Fn,
    builtin: *const fn (allocator: std.mem.Allocator, args: []MalType) MalType,

    /// A basic type to define user made functions
    pub const Fn = struct {
        shared_fn: PageShared(Fn_),

        const Fn_ = struct {
            ast: MalType,
            args: [][]const u8,
            env: *Env,

            pub fn deinit(self: *Fn_, allocator: std.mem.Allocator) void {
                self.ast.deinit(allocator) catch unreachable;
                for (self.args) |arg| {
                    allocator.free(arg);
                }
                allocator.free(self.args);
                self.env.deinit(allocator);
            }
        };

        pub fn init(allocator: std.mem.Allocator, ast: *MalType, args: []MalType, root: *Env) MalType {
            var args_owned = allocator.alloc([]const u8, args.len) catch {
                return makeError(allocator, "Failed to copy args, out of memory.");
            };

            const deinitArgs = struct {
                pub fn f(allocator_: std.mem.Allocator, args_owned_: [][]const u8) void {
                    for (args_owned_) |ao| {
                        allocator_.free(ao);
                    }
                    allocator_.free(args_owned_);
                }
            }.f;

            for (args, 0..) |arg, i| {
                switch (arg) {
                    .symbol => |s| args_owned[i] = allocator.dupe(u8, s.getStr()) catch unreachable,
                    else => {
                        deinitArgs(allocator, args_owned);
                        return makeError(allocator, "Function arguments accept only symbols");
                    },
                }
            }

            const m_fn = PageShared(Fn_).init(Fn_{
                .ast = ast.clone(allocator),
                .args = args_owned,
                .env = root.clone(),
            }) catch {
                deinitArgs(allocator, args_owned);
                return makeError(allocator, "Failed to create function, out of memory");
            };

            const self = Fn{ .shared_fn = m_fn };
            return .{ .function = self };
        }

        pub fn deinit(self: *Fn, allocator: std.mem.Allocator) !void {
            try self.shared_fn.deinit(allocator);
        }
    };

    pub const Array = struct {
        items: PageShared(MArray),
        array_type: ArrayType,

        const ArrayType = enum {
            list,
            vector,
        };

        const MArray = std.ArrayListUnmanaged(MalType);

        fn initArr(allocator: std.mem.Allocator, arr: *MArray) !PageShared(MArray) {
            var items: MArray = .empty;

            for (arr.items) |*item| {
                try items.append(allocator, item.clone(allocator));
            }

            return try PageShared(MArray).init(items);
        }

        pub fn initList(allocator: std.mem.Allocator, arr: *MArray) !MalType {
            const new_arr = try initArr(allocator, arr);
            const list = Array{ .items = new_arr, .array_type = .list };
            return .{ .list = list };
        }

        pub fn emptyList(allocator: std.mem.Allocator) MalType {
            const items: MArray = .empty;
            const new_arr = PageShared(MArray).init(items) catch {
                return makeError(allocator, "Could not create list");
            };
            return .{ .list = .{ .items = new_arr, .array_type = .list } };
        }

        pub fn emptyVector(allocator: std.mem.Allocator) MalType {
            const items: MArray = .empty;
            const new_arr = PageShared(MArray).init(items) catch {
                return makeError(allocator, "Could not create list");
            };
            return .{ .vector = .{ .items = new_arr, .array_type = .vector } };
        }

        pub fn initVector(allocator: std.mem.Allocator, arr: *MArray) !MalType {
            const new_arr = try initArr(allocator, arr);
            const vector = Array{ .items = new_arr, .array_type = .vector };
            return .{ .vector = vector };
        }

        pub fn append(self: *Array, allocator: std.mem.Allocator, value: MalType) MalType {
            self.items.getPtr().append(allocator, value) catch {
                return makeError(allocator, "Could not append to collection, OOM");
            };
            return .nil;
        }

        pub fn add(self: *Array, allocator: std.mem.Allocator, other: *Array) MalType {
            var items: MArray = .initCapacity(allocator, self.getItems().len + other.getItems().len);

            for (self.getItems()) |*item| {
                items.appendAssumeCapacity(allocator, item.clone(allocator));
            }
            for (other.getItems()) |*item| {
                items.appendAssumeCapacity(item.clone(allocator));
            }

            return switch (self.array_type) {
                .list => .{ .list = items },
                .vector => .{ .vector = items },
            };
        }

        pub fn addMut(self: *Array, allocator: std.mem.Allocator, other: *Array) MalType {
            self.items.getPtr().ensureUnusedCapacity(allocator, other.getItems().len) catch {
                return makeError(allocator, "Can not add arrays, Out of Memory");
            };
            for (other.getItems()) |*item| {
                self.items.getPtr().appendAssumeCapacity(item.clone(allocator));
            }
            return .nil;
        }

        pub fn getItems(self: Array) []MalType {
            return self.items.get().items;
        }

        pub fn getItemsPtr(self: Array) *[]MalType {
            return self.items.getPtr().items;
        }

        pub fn clone(self: *Array, allocator: std.mem.Allocator) !MalType {
            return switch (self.array_type) {
                .list => initList(allocator, self.items.getPtr()),
                .vector => initVector(allocator, self.items.getPtr()),
            };
        }

        pub fn deinit(self: *Array, allocator: std.mem.Allocator) SharedError!void {
            for (self.items.getPtr().items) |*item| {
                try item.deinit(allocator);
            }
            try self.items.deinit(allocator);
        }
    };

    /// A basic string type which is basically a wrapper with helper functions to concatenate string and handle its memory.
    pub const String = struct {
        chars: SString,

        const SString = PageShared(std.ArrayListUnmanaged(u8));

        pub fn initFrom(allocator: std.mem.Allocator, str: []const u8) !MalType {
            var chars = try std.ArrayListUnmanaged(u8).initCapacity(allocator, str.len);
            chars.appendSliceAssumeCapacity(str);
            return .{ .string = .{ .chars = try SString.init(chars) } };
        }

        pub fn getStr(self: String) []const u8 {
            return self.chars.get().items;
        }

        /// Concatenates s1 and s2 on a new string
        pub fn add(allocator: std.mem.Allocator, s1: String, s2: String) !MalType {
            var chars = try std.ArrayListUnmanaged(u8).initCapacity(allocator, s1.getStr().len + s2.getStr().len);
            chars.appendSliceAssumeCapacity(s1.getStr());
            chars.appendSliceAssumeCapacity(s2.getStr());
            return .{ .string = .{ .chars = try SString.init(chars) } };
        }

        /// Add s to self
        pub fn addMut(self: *String, allocator: std.mem.Allocator, s: String) !void {
            try self.chars.getPtr().appendSlice(allocator, s.getStr());
        }

        pub fn deinit(self: *String, allocator: std.mem.Allocator) !void {
            try self.chars.deinit(allocator);
        }

        pub fn clone(self: *String, _: std.mem.Allocator) !MalType {
            return .{ .string = .{ .chars = try self.chars.clone() } };
        }
    };

    pub const Dict = struct {
        values: PageShared(Map),

        const Map = std.HashMapUnmanaged(
            MalType,
            MalType,
            Context,
            std.hash_map.default_max_load_percentage,
        );

        pub fn add(self: *Dict, allocator: std.mem.Allocator, key: *MalType, value: *MalType) MalType {
            switch (key.*) {
                .int, .string, .keyword => {
                    self.values.getPtr().put(allocator, key.clone(allocator), value.clone(allocator)) catch {
                        return makeError(allocator, "Allocator error: Could not add value to hash map");
                    };
                    return .nil;
                },
                else => return makeError(allocator, "Unhashable key type"),
            }
        }

        pub fn init() !MalType {
            const values: Map = .empty;
            return .{ .dict = .{ .values = try PageShared(Map).init(values) } };
        }

        pub fn deinit(self: *Dict, allocator: std.mem.Allocator) SharedError!void {
            var iter = self.getValues().iterator();
            while (iter.next()) |entry| {
                try entry.key_ptr.deinit(allocator);
                try entry.value_ptr.deinit(allocator);
            }
            try self.values.deinit(allocator);
        }

        pub fn getValues(self: Dict) Map {
            return self.values.get();
        }

        pub fn clone(self: *Dict, allocator: std.mem.Allocator) !MalType {
            var dict = try init();
            var iter = self.getValues().iterator();
            while (iter.next()) |entry| {
                _ = dict.dict.add(allocator, entry.key_ptr, entry.value_ptr);
            }
            return dict;
        }

        const Context = struct {
            pub fn hash(_: Context, value: MalType) u64 {
                var h: std.hash.Wyhash = .init(0);
                const b = switch (value) {
                    .int => |i| std.mem.asBytes(&i),
                    .string, .keyword => |s| s.getStr(),
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
        return .{ .err = err_msg.string };
    }

    pub fn makeErrorF(allocator: std.mem.Allocator, comptime msg: []const u8, args: anytype) MalType {
        var buffer = std.ArrayList(u8).init(allocator);
        std.fmt.format(buffer.writer(), msg, args) catch {};
        const m = buffer.toOwnedSlice() catch unreachable;
        defer allocator.free(m);

        const err_msg = MalType.String.initFrom(allocator, m) catch {
            return .nil;
        };
        return .{ .err = err_msg.string };
    }

    pub fn clone(self: *MalType, allocator: std.mem.Allocator) MalType {
        return switch (self.*) {
            inline MalType.string, MalType.vector, MalType.list, MalType.dict => |*s| s.clone(allocator) catch .nil,
            MalType.err => |*s| {
                const str = s.clone(allocator) catch {
                    return .nil;
                };
                return .{ .err = str.string };
            },
            MalType.keyword => |*s| {
                const str = s.clone(allocator) catch return .nil;
                return .{ .keyword = str.string };
            },
            MalType.symbol => |*s| {
                const str = s.clone(allocator) catch return .nil;
                return .{ .symbol = str.string };
            },
            else => return self.*,
        };
    }

    pub fn eql(a: MalType, b: MalType) bool {
        return switch (a) {
            .int => |v1| switch (b) {
                .int => |v2| v1 == v2,
                else => false,
            },
            .boolean => |v1| switch (b) {
                .boolean => |v2| v1 == v2,
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
            .symbol => |s1| switch (b) {
                .symbol => |s2| std.mem.eql(u8, s1.getStr(), s2.getStr()),
                else => false,
            },
            .keyword => |s1| switch (b) {
                .keyword => |s2| std.mem.eql(u8, s1.getStr(), s2.getStr()),
                else => false,
            },
            .list => |l1| switch (b) {
                .list => |l2| {
                    const items1 = l1.getItems();
                    const items2 = l2.getItems();
                    if (items1.len != items2.len) return false;
                    for (items1, items2) |v1, v2| {
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
                    const items1 = l1.getItems();
                    const items2 = l2.getItems();
                    if (items1.len != items2.len) return false;
                    for (items1, items2) |v1, v2| {
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
                    const values1 = d1.getValues();
                    const values2 = d2.getValues();
                    if (values1.size != values2.size) return false;
                    var iter = values1.iterator();
                    while (iter.next()) |entry| {
                        if (values2.get(entry.key_ptr.*)) |val| {
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
            .symbol, .keyword => |s| try buffer.appendSlice(s.getStr()),
            .string => |s| try std.fmt.format(buffer.writer(), "\"{s}\"", .{s.getStr()}),
            .err => |s| try std.fmt.format(buffer.writer(), "ERROR: {s}", .{s.getStr()}),
            .nil => try buffer.appendSlice("nil"),
            .list => |l| {
                try buffer.appendSlice("(");
                for (l.getItems(), 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice(")");
            },
            .vector => |a| {
                try buffer.appendSlice("[");
                for (a.getItems(), 0..) |item, i| {
                    if (i > 0) try buffer.append(' ');
                    try item.toStringInternal(buffer);
                }
                try buffer.appendSlice("]");
            },
            .dict => |d| {
                try buffer.appendSlice("{");
                var iter = d.getValues().iterator();
                while (iter.next()) |entry| {
                    try entry.key_ptr.toStringInternal(buffer);
                    try buffer.appendSlice(" ");
                    try entry.value_ptr.toStringInternal(buffer);
                }
                try buffer.appendSlice("}");
            },
            .function => try buffer.appendSlice("#<function>"),
            .builtin => try buffer.appendSlice("#<function><builtin>"),
            inline .int, .float, .boolean => |i| try std.fmt.format(buffer.writer(), "{}", .{i}),
        }
    }

    pub fn deinit(self: *MalType, allocator: std.mem.Allocator) !void {
        switch (self.*) {
            inline MalType.list,
            MalType.vector,
            MalType.dict,
            MalType.string,
            MalType.err,
            MalType.keyword,
            MalType.symbol,
            MalType.function,
            => |*f| {
                try f.deinit(allocator);
            },
            else => return,
        }
    }
};
