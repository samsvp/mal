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
pub fn PageShared(comptime T: type) type {
    return struct {
        ptr: *Ptr,
        is_released: bool,

        const Self = @This();
        const Ptr = struct {
            item: *T,
            count: usize,
        };

        pub fn init(item: T) !Self {
            const item_ptr = try std.mem.Allocator.create(std.heap.page_allocator, T);
            const ptr = try std.mem.Allocator.create(std.heap.page_allocator, Ptr);

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

        pub fn get(self: Self) T {
            return self.ptr.item.*;
        }

        pub fn getPtr(self: Self) *T {
            return self.ptr.item;
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

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) !void {
            try self.release();
            if (self.ptr.count == 0) {
                self.ptr.item.deinit(allocator);
                std.heap.page_allocator.destroy(self.ptr.item);
                std.heap.page_allocator.destroy(self.ptr);
            }
        }

        pub fn deinitManaged(self: *Self) !void {
            try self.release();
            if (self.ptr.count == 0) {
                self.ptr.item.deinit();
                std.heap.page_allocator.destroy(self.ptr.item);
                std.heap.page_allocator.destroy(self.ptr);
            }
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
