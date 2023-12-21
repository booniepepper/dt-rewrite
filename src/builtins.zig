const std = @import("std");
const List = std.SinglyLinkedList;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const builtin = @import("builtin");

const mem = @import("mem.zig");
const free = mem.free;
const Rc = mem.Rc;

const types = @import("types.zig");
const Command = types.Command;
const Quote = types.Quote;
const Val = types.Val;

fn topRef(context: List(Quote)) !*Quote {
    var node = context.first orelse {
        return error.StackUnderflow;
    };
    return &node.data;
}

pub fn def(context: List(Quote)) !void {
    var top = try topRef(context);

    var nameVal = try top.pop();
    defer free(nameVal);

    var commandVal = try top.pop();
    defer free(commandVal);

    var name = switch (nameVal) {
        .command => |cmd| cmd,
        .string => |s| s,
        else => {
            try stderr.print("ERR: name was not stringy\n", .{});
            try top.push(try commandVal.copy());
            try top.push(try nameVal.copy());
            return;
        },
    };

    const q = switch (commandVal) {
        .quote => |q| try q.copy(),
        else => newq: {
            var q = Quote.init(top.allocator);
            try q.push(try commandVal.copy());
            break :newq q;
        },
    };

    try top.define(name.newref(), q);
}

pub fn do(context: List(Quote)) !void {
    var top = try topRef(context);

    var commandVal = try top.pop();
    defer free(commandVal);

    const commandName = switch (commandVal) {
        .command => |name| name,
        .string => |s| s,
        .quote => |q| {
            return try (Command{ .quote = q }).run(.{});
        },
    };

    var command = top.defs.get(commandName) orelse {
        try stderr.print("ERR: command undefined: {s}\n", .{commandName.it.items});
        return try top.push(try commandVal.copy());
    };

    try command.run(context);
}

pub fn dup(context: List(Quote)) !void {
    var top = try topRef(context);

    var val: Val = top.vals.pop();
    try top.push(try val.copy());
    try top.push(val);
}

pub fn drop(context: List(Quote)) !void {
    var top = try topRef(context);

    const val: Val = try top.pop();
    free(val);
}

const writer = if (builtin.is_test) stderr else stdout;

pub fn nl(_: List(Quote)) !void {
    try writer.print("\n", .{});
}

pub fn p(context: List(Quote)) !void {
    var top = try topRef(context);

    var val: Val = try top.pop();
    try val.print(writer);
    free(val);
}
