const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const mem = @import("mem.zig");
const free = mem.free;

const types = @import("types.zig");
const Command = types.Command;
const Dictionary = types.Dictionary;
const Quote = types.Quote;
const String = types.String;
const Val = types.Val;

const builtins = @import("builtins.zig");

pub const Dt = struct {
    allocator: Allocator,
    context: ArrayList(Quote),

    const Self = Dt;

    pub fn init(allocator: Allocator) !Self {
        var main: Quote = try Quote.new(allocator);

        try main.it.defineBuiltin("dup", builtins.dup);
        try main.it.defineBuiltin("drop", builtins.drop);

        var mainCtx = ArrayList(Quote).init(allocator);
        try mainCtx.append(main);

        return .{
            .allocator = allocator,
            .context = mainCtx,
        };
    }

    pub fn deinit(self: Self) void {
        free(self.context);
    }

    pub fn readln(self: *Self) !void {
        var line = try String.new(self.allocator);
        try stdin.streamUntilDelimiter(line.it.writer(), '\n', null);
        try self.run(&line);
    }

    pub fn status(self: Self) !void {
        const v: Val = .{ .quote = self.context.getLast() };
        try v.print(stdout);
        try stdout.print("\n", .{});
    }

    pub fn top(self: *Self) *Quote {
        return &self.context.items[self.context.items.len - 1];
    }

    pub fn push(self: *Self, val: Val) !void {
        var curr = self.top();
        try curr.it.push(val);
    }

    pub fn runtok(self: *Self, tok: []const u8) !void {
        var str = try String.new(std.testing.allocator);
        try str.it.appendSlice(tok);
        try self.run(&str);
    }

    pub fn run(self: *Self, linePtr: *String) !void {
        var line = linePtr.*;

        if (line.it.items.len < 1) {
            return free(line);
        } else if (line.it.items[0] == '"' and line.it.getLast() == '"') {
            _ = line.it.orderedRemove(0);
            _ = line.it.pop();
            return try self.push(.{ .string = line });
        } else if (std.mem.eql(u8, "[", line.it.items)) {
            var q = try Quote.new(self.allocator);
            try self.context.append(q);
        } else if (std.mem.eql(u8, "]", line.it.items)) {
            var q = self.context.pop();
            try self.push(.{ .quote = q });
        } else {
            var dict: Dictionary = self.top().it.defs.it;
            var cmd: Command = dict.get(line) orelse return free(line);
            var context = self.top();
            try cmd.run(context);
        }
        free(line);
    }
};

test "[ \"hello\" ] dup drop drop" {
    var dt = try Dt.init(std.testing.allocator);
    defer free(dt);

    try dt.runtok("[");
    try dt.runtok("\"hello\"");
    try dt.runtok("]");
    try dt.runtok("dup");
    try dt.runtok("drop");
    try dt.runtok("drop");
}
