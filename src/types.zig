const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

const mem = @import("mem.zig");
const free = mem.free;
const canClone = mem.canClone;

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
            .string => |s| try writer.print("\"{s}\"", .{s.it.items}),
            .quote => |q| {
                try writer.print("[ ", .{});
                for (q.it.vals.it.items) |v| {
                    try v.print(writer);
                    try writer.print(" ", .{});
                }
                try writer.print("]", .{});
            },
        }
    }
};

pub const Command = union(enum) {
    builtin: *const fn (*Quote) anyerror!void,
    quote: Quote,

    const Self = @This();

    pub fn run(self: Self, context: *Quote) !void {
        switch (self) {
            .builtin => |cmd| return cmd(context),
            .quote => |cmd| {
                _ = cmd;
                var done = false;
                _ = done;
                return error.Unimplemented;
            },
        }
    }
};

pub const Quote = Rc(QuoteStuff);

pub const Dictionary = HashMap(String, Command, StringContext, std.hash_map.default_max_load_percentage);

pub const QuoteStuff = struct {
    vals: Rc(ArrayList(Val)),
    defs: Rc(Dictionary),

    const Self = @This();

    pub fn new(allocator: Allocator) !Self {
        var vals = try Rc(ArrayList(Val)).new(allocator);
        var defs = try Rc(Dictionary).new(allocator);
        return .{
            .vals = vals,
            .defs = defs,
        };
    }

    pub fn deinit(self: Self) void {
        free(self.vals);
        free(self.defs);
    }
};

pub const String = Rc(ArrayList(u8));
pub const StringContext = struct {
    const Self = @This();
    pub fn hash(_: Self, str: String) u64 {
        return std.hash_map.hashString(str.it.items);
    }
    pub fn eql(_: Self, a: String, b: String) bool {
        return std.mem.eql(u8, a.it.items, b.it.items);
    }
};

/// A reference-counted thing.
pub fn Rc(comptime IT: type) type {
    return struct {
        allocator: Allocator,
        it: IT,
        refs: *usize,

        const Self = @This();

        pub fn new(allocator: Allocator) !Self {
            const it = if (comptime std.meta.trait.hasFn("init")(IT))
                IT.init(allocator)
            else if (comptime std.meta.trait.hasFn("new")(IT))
                try IT.new(allocator)
            else
                undefined;
            const refs = try allocator.create(usize);
            refs.* = 1;
            return .{
                .allocator = allocator,
                .it = it,
                .refs = refs,
            };
        }

        /// Creates a new reference.
        pub fn newref(self: *Self) Self {
            self.refs.* += 1;
            return .{
                .allocator = self.allocator,
                .it = self.it,
                .refs = self.refs,
            };
        }

        /// Creates a clone, allocating a new copy of the string's it.
        pub fn clone(self: *Self) !Self {
            var theClone = try Self.new(self.allocator);
            try theClone.it.ensureTotalCapacity(self.it.items);

            if (canClone(IT)) {
                for (self.it.items) |item| {
                    try theClone.it.append(item.clone());
                }
            } else {
                try theClone.it.appendSlice(self.it.items);
            }

            return theClone;
        }

        /// Releases this reference. If this was the final reference, the
        /// it and the counter are freed.
        pub fn release(self: Self) void {
            self.refs.* -= 1;
            if (self.refs.* == 0) {
                free(self.it);
                self.allocator.destroy(self.refs);
            }
        }
    };
}
