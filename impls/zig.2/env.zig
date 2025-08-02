const std = @import("std");

const MalType = @import("types.zig").MalType;
const core = @import("core.zig");

/// Represents a MAL environment (i.e. a scope).
pub const Env = struct {
    mapping: std.StringHashMapUnmanaged(MalType),
    parent: ?*Env,
    ref_count: usize,

    pub fn init(allocator: std.mem.Allocator) *Env {
        const env = allocator.create(Env) catch unreachable;
        env.* = .{
            .mapping = .empty,
            .parent = null,
            .ref_count = 1,
        };
        return env;
    }

    pub fn initWithParent(allocator: std.mem.Allocator, parent: *Env) *Env {
        const env = allocator.create(Env) catch unreachable;
        env.* = .{
            .mapping = .empty,
            .parent = parent.clone(),
            .ref_count = 1,
        };
        return env;
    }

    /// Creates a new root environment, with the default functions.
    pub fn initRoot(allocator: std.mem.Allocator) !*Env {
        var env = Env.init(allocator);
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "="),
            .{ .builtin = core.eql },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "!="),
            .{ .builtin = core.notEql },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "<"),
            .{ .builtin = core.less },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "<="),
            .{ .builtin = core.lessEql },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, ">"),
            .{ .builtin = core.bigger },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, ">="),
            .{ .builtin = core.biggerEql },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "+"),
            .{ .builtin = core.add },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "-"),
            .{ .builtin = core.sub },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "*"),
            .{ .builtin = core.mul },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "/"),
            .{ .builtin = core.div },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "list"),
            .{ .builtin = core.list },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "list?"),
            .{ .builtin = core.listQuestion },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "empty?"),
            .{ .builtin = core.emptyQuestion },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "count"),
            .{ .builtin = core.count },
        );
        try env.mapping.put(
            allocator,
            try std.mem.Allocator.dupe(allocator, u8, "prn"),
            .{ .builtin = core.prn },
        );
        return env;
    }

    pub fn get(self: Env, key: []const u8) ?MalType {
        return self.mapping.get(key) orelse {
            if (self.parent) |parent| {
                return parent.get(key);
            }
            return null;
        };
    }

    pub fn getPtr(self: Env, key: []const u8) ?*MalType {
        return self.mapping.getPtr(key) orelse {
            if (self.parent) |parent| {
                return parent.getPtr(key);
            }
            return null;
        };
    }

    pub fn set(self: *Env, allocator: std.mem.Allocator, key: []const u8, val: *MalType) MalType {
        const key_owned = std.mem.Allocator.dupe(allocator, u8, key) catch {
            return MalType.makeError(allocator, "Could not copy key, Out of Memory");
        };
        self.mapping.put(allocator, key_owned, val.clone(allocator)) catch {
            return MalType.makeError(allocator, "Could not add to map Out of Memory");
        };
        return .nil;
    }

    pub fn clone(self: *Env) *Env {
        self.ref_count += 1;
        var maybe_parent = self.parent;
        while (maybe_parent) |parent| {
            parent.ref_count += 1;
            maybe_parent = parent.parent;
        }
        return self;
    }

    pub fn deinit(self: *Env, allocator: std.mem.Allocator) void {
        if (self.ref_count == 0) {
            return;
        }

        self.ref_count -= 1;

        if (self.ref_count > 0) {
            return;
        }

        if (self.parent) |_| {
            self.deinitForce(allocator);
        }
    }

    pub fn deinitForce(self: *Env, allocator: std.mem.Allocator) void {
        var iter = self.mapping.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator) catch {};
        }
        self.mapping.deinit(allocator);
        if (self.parent) |parent| {
            parent.deinit(allocator);
        }
        allocator.destroy(self);
    }
};
