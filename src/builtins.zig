const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const builtin = @import("builtin");

const mem = @import("mem.zig");
const free = mem.free;

const types = @import("types.zig");
const Command = types.Command;
const Quote = types.Quote;
const Val = types.Val;

pub fn def(context: *Quote) !void {
    var nameVal = try context.pop();
    var commandVal = try context.pop();

    var name = switch (nameVal) {
        .command => |cmd| cmd,
        .string => |s| s,
        else => {
            try stderr.print("ERR: name was not stringy\n", .{});
            try context.push(commandVal);
            try context.push(nameVal);
            return;
        },
    };

    var command = switch (commandVal) {
        .quote => |q| q,
        else => blk: {
            var newquote = try context.child();
            try newquote.push(commandVal);
            break :blk newquote;
        },
    };

    try context.define(name, command);
}

pub fn do(context: *Quote) !void {
    var commandVal = try context.pop();

    var commandName = switch (commandVal) {
        .command => |cmd| cmd,
        .string => |s| s,
        .quote => |*q| {
            var command = try Command.ofImmediate(q);
            try command.run(context);
            free(command);
            return;
        },
    };

    var command = context.defs.it.get(commandName) orelse {
        try stderr.print("ERR: command undefined: {s}\n", .{commandName.it.items});
        try context.push(commandVal);
        return;
    };

    try command.run(context);
    free(commandVal);
}

pub fn dup(context: *Quote) !void {
    var val: Val = context.vals.it.pop();
    try context.push(try val.copy());
    try context.push(val);
}

pub fn drop(context: *Quote) !void {
    if (context.vals.it.items.len < 1) {
        try stderr.print("ERR: stack underflow\n", .{});
    } else {
        var val: Val = try context.pop();
        free(val);
    }
}

const writer = if (builtin.is_test) stderr else stdout;

pub fn nl(_: *Quote) !void {
    try writer.print("\n", .{});
}

pub fn p(context: *Quote) !void {
    var val: Val = try context.pop();
    try val.print(writer);
    free(val);
}
