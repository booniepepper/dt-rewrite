const std = @import("std");

const stderr = std.io.getStdErr().writer();

const mem = @import("mem.zig");
const free = mem.free;

const types = @import("types.zig");
const Quote = types.Quote;
const Val = types.Val;

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
