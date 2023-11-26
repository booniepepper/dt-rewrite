const std = @import("std");

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

pub fn def(context: *Quote) !void {
    var nameVal = try context.pop();
    defer free(nameVal);

    var commandVal = try context.pop();
    defer free(commandVal);

    var name = switch (nameVal) {
        .command => |cmd| cmd,
        .string => |s| s,
        else => {
            try stderr.print("ERR: name was not stringy\n", .{});
            try context.push(try commandVal.copy());
            try context.push(try nameVal.copy());
            return;
        },
    };

    const q = switch (commandVal) {
        .quote => |q| try q.copy(),
        else => newq: {
            var q = Quote.init(context.allocator);
            try q.push(try commandVal.copy());
            break :newq q;
        },
    };

    try context.define(name.newref(), q);
}

pub fn do(context: *Quote) !void {
    var commandVal = try context.pop();
    defer free(commandVal);

    const commandName = switch (commandVal) {
        .command => |name| name,
        .string => |s| s,
        .quote => |q| return try (Command{ .quote = q }).run(context),
    };

    var command = context.defs.get(commandName) orelse {
        try stderr.print("ERR: command undefined: {s}\n", .{commandName.it.items});
        return try context.push(try commandVal.copy());
    };

    try command.run(context);
}

pub fn dup(context: *Quote) !void {
    var val: Val = context.vals.pop();
    try context.push(try val.copy());
    try context.push(val);
}

pub fn drop(context: *Quote) !void {
    const val: Val = try context.pop();
    free(val);
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
