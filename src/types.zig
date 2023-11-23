const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const SinglyLinkedList = std.SinglyLinkedList;
const HashMap = std.HashMap;

const stderr = std.io.getStdErr().writer();

const mem = @import("mem.zig");
const Rc = mem.Rc;
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
            .quote => |*q| .{ .quote = q.newref() },
            .string => |*s| .{ .string = s.newref() },
        };
    }

    pub fn print(self: Self, writer: anytype) !void {
        switch (self) {
            .command => |cmd| try writer.print("{s}", .{cmd.it.items}),
            .quote => |q| {
                try writer.print("[ ", .{});
                for (q.it.vals.it.items) |v| {
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
    quote: Quote,

    const Self = @This();

    pub fn ofImmediate(quote: *Quote) !Self {
        return .{ .quote = quote.newref() };
    }

    pub fn run(self: Self, context: *Quote) !void {
        switch (self) {
            .builtin => |cmd| return cmd(context),
            else => {},
        }

        var quote = self.quote;
        var runCtx = &quote;

        const DL = SinglyLinkedList(Dictionary);
        var deflist = DL{};
        var defs = DL.Node{ .data = context.it.defs.it };
        deflist.prepend(&defs);

        var done = false;
        while (!done) {
            done = true;

            var vals: ArrayList(Val) = runCtx.it.vals.it;
            var thisDefs = DL.Node{ .data = runCtx.it.defs.it };
            deflist.prepend(&thisDefs);

            for (vals.items, 0..) |*val, i| {
                const isTailCall = i == vals.items.len - 1;
                switch (val.*) {
                    .command => |*cmd| {
                        var command = lookup(deflist, cmd) orelse {
                            try stderr.print("ERR: undefined command {s}\n", .{cmd.it.items});
                            return;
                        };
                        switch (command) {
                            .builtin => try command.run(runCtx),
                            .quote => |next| {
                                var nextCtx = next;
                                if (isTailCall) {
                                    done = false;
                                    runCtx = &nextCtx;
                                    // TODO: Smush defs on tail calls for correctness and memory efficiency
                                } else {
                                    try command.run(&nextCtx);
                                }
                            },
                        }
                    },
                    else => try runCtx.it.push(try val.copy()),
                }
            }
        }
    }

    fn lookup(deflist: SinglyLinkedList(Dictionary), cmd: *String) ?Command {
        var it = deflist.first;
        while (it) |node| : (it = node.next) {
            if (node.data.getPtr(cmd.*)) |command| {
                var theCommand = command;
                return theCommand.newref();
            }
        }
        return null;
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
// TODO: Implement a Ctrie. https://en.wikipedia.org/wiki/Ctrie
pub const Dictionary = HashMap(String, Command, StringContext, std.hash_map.default_max_load_percentage);

pub const Quote = Rc(Context);

pub const Context = struct {
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

    pub fn copy(self: Self) Self {
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

    /// Defines a dynamic dt command. Creates a new references for the name,
    /// and copies the quote.
    ///
    /// If this is performed in a "child" quote that was referring to
    /// an existing
    pub fn define(self: *Self, name: String, quote: Quote) !void {
        if (self.defs.refs.* > 1) {
            var newDefs = try self.defs.clone();
            self.defs.release();
            self.defs = newDefs;
        }

        var prev = try self.defs.it.fetchPut(name, .{ .quote = quote.newref() });

        if (prev != null) {
            free(prev.?.key);
            free(prev.?.value);
        }
    }

    /// Defines a built-in dt command. Allocates a String for the name, and
    /// assumes there will be no name conflicts.
    pub fn defineBuiltin(self: *Self, name: []const u8, builtin: *const fn (*Quote) anyerror!void) !void {
        var nameString: String = try String.new(self.allocator);
        try nameString.it.appendSlice(name);
        try self.defs.it.putNoClobber(nameString, .{ .builtin = builtin });
    }

    pub fn push(self: *Self, val: Val) !void {
        // TODO: copy on write!
        try self.vals.it.append(val);
    }

    pub fn pop(self: *Self) !Val {
        // TODO: copy on write!
        if (self.vals.it.items.len == 0) {
            return error.StackUnderflow;
        }
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
