const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

const mem = @import("mem.zig");
const free = mem.free;
const canClone = mem.canClone;

pub const Val = union(enum) {
    command: String,
    quote: Quote,
    string: String,

    const Self = Val;

    pub fn deinit(self: Self) void {
        switch (self) {
            .command => |cmd| free(cmd),
            .quote => |q| free(q),
            .string => |s| free(s),
        }
    }

    pub fn copy(self: *Self) !Self {
        return switch (self.*) {
            .command => |*cmd| .{ .command = cmd.newref() },
            .quote => |*q| .{ .quote = q.copy() },
            .string => |*s| .{ .string = s.newref() },
        };
    }

    pub fn print(self: Self, writer: anytype) !void {
        switch (self) {
            .command => |cmd| try writer.print("{s}", .{cmd.it.items}),
            .quote => |q| {
                try writer.print("[ ", .{});
                for (q.vals.it.items) |v| {
                    try v.print(writer);
                    try writer.print(" ", .{});
                }
                try writer.print("]", .{});
            },
            .string => |s| try writer.print("\"{s}\"", .{s.it.items}),
        }
    }
};

pub const Command = union(enum) {
    builtin: *const fn (*Quote) anyerror!void,
    quote: Rc(Quote),

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

    pub fn deinit(self: Self) void {
        switch (self) {
            .builtin => {},
            .quote => |q| free(q),
        }
    }

    pub fn newref(self: *Self) Self {
        return switch (self.*) {
            .builtin => self.*,
            .quote => |*q| .{ .quote = q.newref() },
        };
    }
};

// Golly a persistent map would be nice around here.
pub const Dictionary = HashMap(String, Command, StringContext, std.hash_map.default_max_load_percentage);

pub const Quote = struct {
    vals: Rc(ArrayList(Val)),
    defs: Rc(Dictionary),
    allocator: Allocator,

    const Self = @This();

    pub fn new(allocator: Allocator) !Self {
        var vals = try Rc(ArrayList(Val)).new(allocator);
        var defs = try Rc(Dictionary).new(allocator);
        return .{
            .vals = vals,
            .defs = defs,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        free(self.vals);
        free(self.defs);
    }

    pub fn copy(self: *Self) Self {
        return .{
            .vals = self.vals.newref(),
            .defs = self.defs.newref(),
            .allocator = self.allocator,
        };
    }

    pub fn child(self: *Self) !Self {
        var vals = try Rc(ArrayList(Val)).new(self.allocator);
        return .{
            .vals = vals,
            .defs = self.defs.newref(),
            .allocator = self.allocator,
        };
    }

    pub fn define(self: *Self, name: String, quote: Quote) !void {
        if (self.defs.refs.* > 1) {
            var newDefs = try self.defs.clone();
            self.defs.release();
            self.defs = newDefs;
        }

        const refs = try self.allocator.create(usize);
        refs.* = 1;
        var command = Rc(Quote){
            .allocator = self.allocator,
            .it = quote,
            .refs = refs,
        };

        var prev = try self.defs.it.fetchPut(name, .{ .quote = command });

        if (prev != null) {
            free(prev.?.key);
            free(prev.?.value);
        }
    }

    pub fn defineBuiltin(self: *Self, name: []const u8, builtin: *const fn (*Quote) anyerror!void) !void {
        var nameString: String = try String.new(self.allocator);
        try nameString.it.appendSlice(name);
        try self.defs.it.putNoClobber(nameString, .{ .builtin = builtin });
    }

    pub fn push(self: *Self, val: Val) !void {
        try self.vals.it.append(val);
    }

    pub fn pop(self: *Self) !Val {
        const val = self.vals.it.pop();
        return val;
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

pub fn makeString(raw: []const u8, allocator: Allocator) !String {
    var string: String = try String.new(allocator);
    try string.it.appendSlice(raw);
    return string;
}

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

            if (IT == Dictionary) {
                var entries = self.it.iterator();
                while (entries.next()) |entry| {
                    try theClone.it.put(entry.key_ptr.newref(), entry.value_ptr.newref());
                }
                return theClone;
            }

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
