const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Val = union(enum) {
    string: String,

    const Self = Val;

    pub fn deinit(self: Self) void {
        switch (self) {
            .string => |s| s.release(),
        }
    }

    pub fn clone(self: *Self) !Self {
        return switch (self.*) {
            .string => |*s| .{ .string = s.newref() },
        };
    }

    pub fn print(self: Self, writer: anytype) !void {
        switch (self) {
            .string => |s| try writer.print("\"{s}\"", .{s.contents.items}),
        }
    }
};

pub const String = struct {
    allocator: Allocator,
    contents: ArrayList(u8),
    refs: *usize,

    const Self = String;

    pub fn new(allocator: Allocator) !Self {
        const contents = ArrayList(u8).init(allocator);
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
        var theClone = try String.new(self.allocator);
        try theClone.contents.appendSlice(self.contents.items);
        return theClone;
    }

    pub fn release(self: Self) void {
        self.refs.* -= 1;
        if (self.refs.* == 0) {
            self.contents.deinit();
            self.allocator.destroy(self.refs);
        }
    }
};
