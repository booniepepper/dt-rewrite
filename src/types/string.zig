const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const mem = @import("../mem.zig");
const Rc = mem.Rc;

pub const String = Rc(ArrayList(u8));

pub const StringContext = struct {
    const Self = @This();
    pub fn hash(_: Self, s: String) u64 {
        return std.hash_map.hashString(s.it.items);
    }
    pub fn eql(_: Self, a: String, b: String) bool {
        return std.mem.eql(u8, a.it.items, b.it.items);
    }
};

pub const ByteArrayContext = struct {
    const Self = @This();
    pub fn hash(_: Self, s: []const u8) u64 {
        return std.hash_map.hashString(s);
    }
    pub fn eql(_: Self, a: []const u8, b: String) bool {
        return std.mem.eql(u8, a, b.it.items);
    }
};

pub fn makeString(raw: []const u8, allocator: Allocator) !String {
    var string: String = try String.new(allocator);
    try string.it.appendSlice(raw);
    return string;
}
