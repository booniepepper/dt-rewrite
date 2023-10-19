const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

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
        for (self.context.items) |ctx| {
            for (ctx.contents.items) |val| {
                val.deinit();
            }
            ctx.release();
        }
        self.context.deinit();
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
        var val: Val = top.contents.pop();
        val.deinit();
        try self.context.append(top);
    }

    pub fn readln(self: *Self) !void {
        var line = try String.new(self.allocator);
        try stdin.streamUntilDelimiter(line.contents.writer(), '\n', null);
        if (line.contents.items[0] == '"' and line.contents.getLast() == '"') {
            _ = line.contents.orderedRemove(0);
            _ = line.contents.pop();
            try self.push(.{ .string = line });
        } else if (std.mem.eql(u8, "dup", line.contents.items)) {
            try self.dup();
        } else if (std.mem.eql(u8, "drop", line.contents.items)) {
            try self.drop();
        }
    }

    pub fn status(self: Self) !void {
        const v: Val = .{ .quote = self.context.getLast() };
        try v.print(stdout);
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
