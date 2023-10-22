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
        try top.it.vals.it.append(val);
        try self.context.append(top);
    }

    pub fn pop(self: *Self) !Val {
        var top: Quote = self.context.pop();
        const val = top.it.vals.it.pop();
        try self.context.append(top);
        return val;
    }

    pub fn dup(self: *Self) !void {
        var top: Quote = self.context.pop();
        var val: Val = top.it.vals.it.pop();
        try top.it.vals.it.append(try val.copy());
        try top.it.vals.it.append(val);
        try self.context.append(top);
    }

    pub fn drop(self: *Self) !void {
        var top: Quote = self.context.pop();
        if (top.it.vals.it.items.len < 1) {
            try stderr.print("ERR: stack underflow\n", .{});
        } else {
            var val: Val = top.it.vals.it.pop();
            free(val);
        }
        try self.context.append(top);
    }

    pub fn readln(self: *Self) !void {
        var line = try String.new(self.allocator);
        try stdin.streamUntilDelimiter(line.it.writer(), '\n', null);
        try self.run(&line);
    }

    pub fn run(self: *Self, linePtr: *String) !void {
        var line = linePtr.*;

        if (line.it.items.len < 1) {
            return free(line);
        } else if (line.it.items[0] == '"' and line.it.getLast() == '"') {
            _ = line.it.orderedRemove(0);
            _ = line.it.pop();
            return try self.push(.{ .string = line });
        } else if (std.mem.eql(u8, "dup", line.it.items)) {
            try self.dup();
        } else if (std.mem.eql(u8, "drop", line.it.items)) {
            try self.drop();
        } else if (std.mem.eql(u8, "[", line.it.items)) {
            var q = try Quote.new(self.allocator);
            try self.context.append(q);
        } else if (std.mem.eql(u8, "]", line.it.items)) {
            var q = self.context.pop();
            var top = self.context.pop();
            try top.it.vals.it.append(.{ .quote = q });
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
    try s.it.appendSlice("hello");
    try dt.push(.{ .string = s });

    var val = try dt.pop();
    val.deinit();
}

test "dup" {
    var dt = try Dt.init(std.testing.allocator);
    defer dt.deinit();

    var s = try String.new(std.testing.allocator);
    try s.it.appendSlice("hello");
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
    try s.it.appendSlice("hello");
    try dt.push(.{ .string = s });

    try dt.drop();
}

test "[ \"hello\" ] dup drop drop" {
    var dt = try Dt.init(std.testing.allocator);
    defer dt.deinit();

    var openBracket = try String.new(std.testing.allocator);
    try openBracket.it.appendSlice("[");
    var helloString = try String.new(std.testing.allocator);
    try helloString.it.appendSlice("\"hello\"");
    var closeBracket = try String.new(std.testing.allocator);
    try closeBracket.it.appendSlice("]");

    try dt.run(&openBracket);
    try dt.run(&helloString);
    try dt.run(&closeBracket);

    // try dt.status();

    try dt.dup();
    try dt.drop();
    try dt.drop();
}
