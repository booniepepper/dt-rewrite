const std = @import("std");

const stderr = std.io.getStdErr().writer();

const mem = @import("mem.zig");
const free = mem.free;

const types = @import("types.zig");
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
