const std = @import("std");

pub const canClone = std.meta.trait.hasFn("clone");

const canRelease = std.meta.trait.hasFn("release");
const canDeinit = std.meta.trait.hasFn("deinit");
const hasItems = std.meta.trait.hasField("items");

pub fn free(thing: anytype) void {
    const T = @TypeOf(thing);
    if (comptime hasItems(T)) for (thing.items) |item| free(item);
    if (comptime canDeinit(T)) thing.deinit();
    if (comptime canRelease(T)) thing.release();
}
