const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const mem = @import("mem.zig");
const free = mem.free;

const types = @import("types.zig");
const Val = types.Val;
const String = types.String;
const Quote = types.Quote;

pub const Dt = struct {
    allocator: Allocator,
    context: ArrayList(Quote),

    const Self = Dt;

    pub fn init(allocator: Allocator) !Self {
        var main = try Quote.new(allocator);
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

    pub fn push(self: *Self, val: Val) !void {
        var top: Quote = self.context.pop();
        try top.contents.append(val);
        try self.context.append(top);
    }

    pub fn pop(self: *Self) !Val {
        var top: Quote = self.context.pop();
        const val = top.contents.pop();
        try self.context.append(top);
        return val;
    }

    pub fn dup(self: *Self) !void {
        var top: Quote = self.context.pop();
        var val: Val = top.contents.pop();
        try top.contents.append(try val.copy());
        try top.contents.append(val);
        try self.context.append(top);
    }

    pub fn drop(self: *Self) !void {
        var top: Quote = self.context.pop();
        if (top.contents.items.len < 1) {
            try stderr.print("ERR: stack underflow\n", .{});
        } else {
            var val: Val = top.contents.pop();
            free(val);
        }
        try self.context.append(top);
    }

    pub fn readln(self: *Self) !void {
        var line = try String.new(self.allocator);
        try stdin.streamUntilDelimiter(line.contents.writer(), '\n', null);
        try self.run(&line);
    }

    pub fn run(self: *Self, linePtr: *String) !void {
        var line = linePtr.*;

        if (line.contents.items.len < 1) {
            return free(line);
        } else if (line.contents.items[0] == '"' and line.contents.getLast() == '"') {
            _ = line.contents.orderedRemove(0);
            _ = line.contents.pop();
            return try self.push(.{ .string = line });
        } else if (std.mem.eql(u8, "dup", line.contents.items)) {
            try self.dup();
        } else if (std.mem.eql(u8, "drop", line.contents.items)) {
            try self.drop();
        } else if (std.mem.eql(u8, "[", line.contents.items)) {
            var q = try Quote.new(self.allocator);
            try self.context.append(q);
        } else if (std.mem.eql(u8, "]", line.contents.items)) {
            var q = self.context.pop();
            var top = self.context.pop();
            try top.contents.append(.{ .quote = q });
            try self.context.append(top);
        }
        free(line);
    }

    pub fn status(self: Self) !void {
        const v: Val = .{ .quote = self.context.getLast() };
        try v.print(stdout);
        try stdout.print("\n", .{});
    }
};

test "pushpop" {
    var dt = try Dt.init(std.testing.allocator);
    defer dt.deinit();

    var s = try String.new(std.testing.allocator);
    try s.contents.appendSlice("hello");
    try dt.push(.{ .string = s });

    var val = try dt.pop();
    val.deinit();
}

test "dup" {
    var dt = try Dt.init(std.testing.allocator);
    defer dt.deinit();

    var s = try String.new(std.testing.allocator);
    try s.contents.appendSlice("hello");
    try dt.push(.{ .string = s });

    try dt.dup();

    var val1 = try dt.pop();
    val1.deinit();
    var val2 = try dt.pop();
    val2.deinit();
}

test "drop" {
    var dt = try Dt.init(std.testing.allocator);
    defer dt.deinit();

    var s = try String.new(std.testing.allocator);
    try s.contents.appendSlice("hello");
    try dt.push(.{ .string = s });

    try dt.drop();
}

test "[ \"hello\" ] dup drop drop" {
    var dt = try Dt.init(std.testing.allocator);
    defer dt.deinit();

    var openBracket = try String.new(std.testing.allocator);
    try openBracket.contents.appendSlice("[");
    var helloString = try String.new(std.testing.allocator);
    try helloString.contents.appendSlice("\"hello\"");
    var closeBracket = try String.new(std.testing.allocator);
    try closeBracket.contents.appendSlice("]");

    try dt.run(&openBracket);
    try dt.run(&helloString);
    try dt.run(&closeBracket);

    // try dt.status();

    try dt.dup();
    try dt.drop();
    try dt.drop();
}
