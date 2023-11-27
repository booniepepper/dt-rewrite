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

const string = @import("types/string.zig");
pub const String = string.String;
const StringContext = string.StringContext;
pub const makeString = string.makeString;

pub const Val = union(enum) {
    command: String,
    quote: Quote,
    string: String,

    const Self = Val;

    /// Calls mem.free() on the command, quote, or string owned by this Val.
    pub fn deinit(self: Self) void {
        switch (self) {
            .command => |cmd| free(cmd),
            .quote => |q| free(q),
            .string => |s| free(s),
        }
    }

    /// Copies a Val.
    ///
    /// - Primitives are simple copies
    /// - Quotes are cloned val-by-val (recursively) and def-by-def
    /// - Strings have their reference count increased
    pub fn copy(self: *Self) anyerror!Self {
        return switch (self.*) {
            .command => |*cmd| .{ .command = cmd.newref() },
            .quote => |q| .{ .quote = try q.copy() },
            .string => |*s| .{ .string = s.newref() },
        };
    }

    /// Prints the value to the writer.
    pub fn print(self: Self, writer: anytype) !void {
        switch (self) {
            .command => |cmd| try writer.print("{s}", .{cmd.it.items}),
            .quote => |q| {
                try writer.print("[ ", .{});
                // TODO: Sneak in local defs here.
                for (q.vals.items) |v| {
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

    pub fn run(self: Self, context: *Quote) !void {
        switch (self) {
            .builtin => |cmd| return cmd(context),
            else => {},
        }

        var quote = self.quote;
        var runCtx = &quote;

        const DL = SinglyLinkedList(Dictionary);
        var deflist = DL{};
        var defs = DL.Node{ .data = context.defs };
        deflist.prepend(&defs);

        var done = false;
        while (!done) {
            done = true;

            const vals: ArrayList(Val) = runCtx.vals;
            var thisDefs = DL.Node{ .data = runCtx.defs };
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
                    else => try runCtx.push(try val.copy()),
                }
            }
        }
    }

    fn lookup(deflist: SinglyLinkedList(Dictionary), cmd: *String) ?Command {
        var it = deflist.first;
        while (it) |node| : (it = node.next) {
            if (node.data.get(cmd.*)) |command| {
                return command;
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

    pub fn copy(self: *Self) !Self {
        return switch (self.*) {
            .builtin => self.*,
            .quote => |q| .{ .quote = try q.copy() },
        };
    }
};

// Golly a persistent map would be nice around here.
// TODO: Implement a Ctrie. https://en.wikipedia.org/wiki/Ctrie
pub const Dictionary = HashMap(String, Command, StringContext, std.hash_map.default_max_load_percentage);

pub const Quote = struct {
    vals: ArrayList(Val),
    defs: Dictionary,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        const vals = ArrayList(Val).init(allocator);
        const defs = Dictionary.init(allocator);
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

    pub fn copy(self: Self) anyerror!Self {
        var new = Quote.init(self.allocator);
        for (self.vals.items) |*val| {
            const newVal = try val.copy();
            try stderr.print("Copying {any}\n", .{newVal});
            try new.vals.append(newVal);
        }

        var entries = self.defs.iterator();
        while (entries.next()) |entry| {
            try new.defs.put(entry.key_ptr.newref(), try entry.value_ptr.copy());
        }

        return new;
    }

    // pub fn child(self: *Self) !Self {
    //     const vals = ArrayList(Val).init(self.allocator);
    //     var defs = Dictionary.init(self.allocator);

    //     var entries = self.defs.iterator();
    //     while (entries.next()) |entry| {
    //         try defs.put(entry.key_ptr.newref(), try entry.value_ptr.copy());
    //     }

    //     return .{
    //         .vals = vals,
    //         .defs = defs,
    //         .allocator = self.allocator,
    //     };
    // }

    /// Defines a dynamic dt command. Any copies should be made before calling this.
    ///
    /// If this is performed in a "child" quote that was referring to
    /// an existing
    pub fn define(self: *Self, name: String, quote: Quote) !void {
        const prev = try self.defs.fetchPut(name, .{ .quote = quote });

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
        try self.defs.putNoClobber(nameString, .{ .builtin = builtin });
    }

    pub fn push(self: *Self, val: Val) !void {
        // TODO: copy on write!
        try self.vals.append(val);
    }

    pub fn pop(self: *Self) !Val {
        // TODO: copy on write!
        if (self.vals.items.len == 0) {
            return error.StackUnderflow;
        }
        const val = self.vals.pop();
        return val;
    }
};
