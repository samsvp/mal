const std = @import("std");

pub const SharedErrors = error{
    ResourceReleased,
    ResourceAlreadyFreed,
};

/// Type which implements a simple reference counter to a concrete type which needs to free
/// underlying heap allocated data (e.g. an ArrayList). The passed object will be copied to the heap using the passed
/// allocator.
/// Call clone to receive the shared object and increase the reference counter. Call `deinit(allocator)` to decrement the
/// reference counter. Once the reference counter reaches zero, `deinit(allocator)` is called
/// and the pointer is made invalid. If the type is managed (i.e. it keeps an allocator reference)
/// then call `deinitManaged()`.
pub fn Shared(comptime T: type) type {
    return struct {
        ptr: *Ptr,
        is_released: bool,

        const Self = @This();
        const Ptr = struct {
            item: *T,
            count: usize,
        };

        pub fn init(ptr_allocator: std.mem.Allocator, item: T) !Self {
            const item_ptr = try std.mem.Allocator.create(ptr_allocator, T);
            const ptr = try std.mem.Allocator.create(ptr_allocator, Ptr);

            item_ptr.* = item;
            ptr.* = .{
                .item = item_ptr,
                .count = 1,
            };

            return .{
                .ptr = ptr,
                .is_released = false,
            };
        }

        pub fn clone(self: *Self) !Self {
            if (self.is_released) {
                return SharedErrors.ResourceReleased;
            }

            self.ptr.count += 1;
            return self.*;
        }

        fn release(self: *Self) !void {
            if (self.is_released) {
                return SharedErrors.ResourceAlreadyFreed;
            }

            self.ptr.count -= 1;
            self.is_released = true;
        }

        pub fn deinit(self: *Self, ptr_allocator: std.mem.Allocator, allocator: std.mem.Allocator) !void {
            try self.release();
            if (self.ptr.count == 0) {
                self.ptr.item.deinit(allocator);
                ptr_allocator.destroy(self.ptr.item);
                ptr_allocator.destroy(self.ptr);
            }
        }

        pub fn deinitManaged(self: *Self, ptr_allocator: std.mem.Allocator) !void {
            try self.release();
            if (self.ptr.count == 0) {
                self.ptr.item.deinit();
                ptr_allocator.destroy(self.ptr.item);
                ptr_allocator.destroy(self.ptr);
            }
        }
    };
}

/// A shared implementation which uses a page allocator as the allocator for the `ptr_allocator`
/// param of the `Shared` type.
pub fn PageShared(comptime T: type) type {
    return struct {
        shared: Shared(T),

        const Self = @This();

        pub fn init(item: T) !Self {
            const shared: Shared(T) = try .init(std.heap.page_allocator, item);
            return .{ .shared = shared };
        }

        pub fn clone(self: *Self) !Self {
            return .{ .shared = try self.shared.clone() };
        }

        fn release(self: *Self) !void {
            self.shared.release();
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) !void {
            try self.shared.deinit(std.heap.page_allocator, allocator);
        }

        pub fn deinitManaged(self: *Self) !void {
            try self.shared.deinitManaged(std.heap.page_allocator);
        }
    };
}

test "Test counting" {
    const MalType = @import("types.zig").MalType;

    const myFn = struct {
        fn f(allocator: std.mem.Allocator, s: *PageShared(MalType)) !void {
            var x = try s.clone();
            try x.deinit(allocator);
        }
    }.f;

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    const str = try MalType.String.initFrom(allocator, "hello");
    const x = MalType{ .string = str };
    var s_x: PageShared(MalType) = try .init(x);
    var s_x2 = try s_x.clone();
    try s_x.deinit(allocator);
    try myFn(allocator, &s_x2);
    try s_x2.deinit(allocator);

    const deinit_status = gpa.deinit();
    if (deinit_status == .leak) {
        std.debug.print("WARNING: memory leaked\n", .{});
        try std.testing.expect(false);
    }
}
