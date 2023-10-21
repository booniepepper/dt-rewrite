const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Val = union(enum) {
    string: String,
    quote: Quote,

    const Self = Val;

    pub fn deinit(self: Self) void {
        switch (self) {
            .string => |s| free(s),
            .quote => |q| free(q),
        }
    }

    pub fn copy(self: *Self) !Self {
        return switch (self.*) {
            .string => |*s| .{ .string = s.newref() },
            .quote => |*q| .{ .quote = q.newref() },
        };
    }

    pub fn print(self: Self, writer: anytype) !void {
        switch (self) {
            .string => |s| try writer.print("\"{s}\"", .{s.contents.items}),
            .quote => |q| {
                try writer.print("[ ", .{});
                for (q.contents.items) |v| {
                    try v.print(writer);
                    try writer.print(" ", .{});
                }
                try writer.print("]", .{});
            },
        }
    }
};

const canClone = std.meta.trait.hasFn("clone");

const canRelease = std.meta.trait.hasFn("release");
const canDeinit = std.meta.trait.hasFn("deinit");
const hasItems = std.meta.trait.hasField("items");

pub fn free(thing: anytype) void {
    const T = @TypeOf(thing);
    if (comptime hasItems(T)) for (thing.items) |item| free(item);
    if (comptime canDeinit(T)) thing.deinit();
    if (comptime canRelease(T)) thing.release();
}

pub const String = RcArrayList(u8);
pub const Quote = RcArrayList(Val);

/// A reference-counted array list.
pub fn RcArrayList(comptime T: type) type {
    return struct {
        allocator: Allocator,
        contents: ArrayList(T),
        refs: *usize,

        const Self = @This();

        pub fn new(allocator: Allocator) !Self {
            const contents = ArrayList(T).init(allocator);
            const refs = try allocator.create(usize);
            refs.* = 1;
            return .{
                .allocator = allocator,
                .contents = contents,
                .refs = refs,
            };
        }

        /// Creates a new reference.
        pub fn newref(self: *Self) Self {
            self.refs.* += 1;
            return .{
                .allocator = self.allocator,
                .contents = self.contents,
                .refs = self.refs,
            };
        }

        /// Creates a clone, allocating a new copy of the string's contents.
        pub fn clone(self: *Self) !Self {
            var theClone = try Self.new(self.allocator);
            try theClone.contents.ensureTotalCapacity(self.contents.items);

            if (canClone(T)) {
                for (self.contents.items) |item| {
                    try theClone.contents.append(item.clone());
                }
            } else {
                try theClone.contents.appendSlice(self.contents.items);
            }

            return theClone;
        }

        /// Releases this reference. If this was the final reference, the
        /// contents and the counter are freed.
        pub fn release(self: Self) void {
            self.refs.* -= 1;
            if (self.refs.* == 0) {
                free(self.contents);
                self.allocator.destroy(self.refs);
            }
        }
    };
}
