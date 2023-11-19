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
    var nameVal = try context.it.pop();
    var commandVal = try context.it.pop();

    var name = switch (nameVal) {
        .command => |cmd| cmd,
        .string => |s| s,
        else => {
            try stderr.print("ERR: name was not stringy\n", .{});
            try context.it.push(commandVal);
            try context.it.push(nameVal);
            return;
        },
    };

    var command = switch (commandVal) {
        .quote => |q| q,
        else => {
            var newquote = try Quote.new(context.it.allocator);
            newquote.it = try context.it.child();
            try newquote.it.push(commandVal);
            return try context.it.define(name.newref(), newquote);
        },
    };

    try context.it.define(name, command);
}

pub fn do(context: *Quote) !void {
    var commandVal = try context.it.pop();

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

    var command = context.it.defs.it.get(commandName) orelse {
        try stderr.print("ERR: command undefined: {s}\n", .{commandName.it.items});
        try context.it.push(commandVal);
        return;
    };

    try command.run(context);
    free(commandVal);
}

pub fn dup(context: *Quote) !void {
    var val: Val = context.it.vals.it.pop();
    try context.it.push(try val.copy());
    try context.it.push(val);
}

pub fn drop(context: *Quote) !void {
    if (context.it.vals.it.items.len < 1) {
        try stderr.print("ERR: stack underflow\n", .{});
    } else {
        var val: Val = try context.it.pop();
        free(val);
    }
}

const writer = if (builtin.is_test) stderr else stdout;

pub fn nl(_: *Quote) !void {
    try writer.print("\n", .{});
}

pub fn p(context: *Quote) !void {
    var val: Val = try context.it.pop();
    try val.print(writer);
    free(val);
}
