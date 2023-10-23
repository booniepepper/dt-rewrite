const builtin = @import("builtin");

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
const makeString = types.makeString;

const builtins = @import("builtins.zig");

pub const Dt = struct {
    allocator: Allocator,
    context: ArrayList(Quote),

    const Self = Dt;

    pub fn init(allocator: Allocator) !Self {
        var main: Quote = try Quote.new(allocator);

        try main.defineBuiltin("def", builtins.def);
        try main.defineBuiltin("do", builtins.do);
        try main.defineBuiltin("drop", builtins.drop);
        try main.defineBuiltin("dup", builtins.dup);

        if (comptime builtin.mode == .Debug) {
            var nothing = try makeString("nothing", allocator);
            var nothingBody: Quote = try Quote.new(allocator);
            try main.define(nothing, nothingBody);
        }

        var context = ArrayList(Quote).init(allocator);
        try context.append(main);

        return .{
            .allocator = allocator,
            .context = context,
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

    pub fn isMain(self: Self) bool {
        return self.context.items.len == 1;
    }

    pub fn top(self: *Self) *Quote {
        return &self.context.items[self.context.items.len - 1];
    }

    pub fn push(self: *Self, val: Val) !void {
        var curr = self.top();
        try curr.push(val);
    }

    pub fn runtok(self: *Self, tok: []const u8) !void {
        var string = try makeString(tok, self.allocator);
        try self.run(&string);
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
            var q = try self.top().child();
            try self.context.append(q);
            return free(line);
        } else if (std.mem.eql(u8, "]", line.it.items)) {
            var q = self.context.pop();
            try self.push(.{ .quote = q });
            return free(line);
        } else if (self.isMain()) {
            var dict: Dictionary = self.top().defs.it;
            var cmd: Command = dict.get(line) orelse return free(line);
            var context = self.top();
            try cmd.run(context);
            return free(line);
        }
        return try self.push(.{ .command = line });
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

test "[ \"hello\" ] \"greet\" def   \"greet\" do" {
    var dt = try Dt.init(std.testing.allocator);
    defer free(dt);

    try dt.runtok("[");
    try dt.runtok("\"hello\"");
    try dt.runtok("]");
    try dt.runtok("\"greet\"");
    try dt.runtok("def");
    try dt.runtok("\"greet\"");
    try dt.runtok("do");
}
