const std = @import("std");

pub const canClone = std.meta.trait.hasFn("clone");

const canRelease = std.meta.trait.hasFn("release");
const canDeinit = std.meta.trait.hasFn("deinit");
const hasItems = std.meta.trait.hasField("items");
const hasKeys = std.meta.trait.hasFn("keyIterator");
const hasValues = std.meta.trait.hasFn("valueIterator");

pub fn free(something: anytype) void {
    const T = @TypeOf(something);
    var thing = something;

    if (comptime std.meta.trait.isSingleItemPtr(T)) return free(thing.*);

    if (comptime hasItems(T)) for (thing.items) |item| free(item);
    if (comptime hasKeys(T)) {
        var it = thing.keyIterator();
        while (it.next()) |key| free(key);
    }
    if (comptime hasValues(T)) {
        var it = thing.valueIterator();
        while (it.next()) |value| free(value);
    }

    if (comptime canDeinit(T)) thing.deinit();
    if (comptime canRelease(T)) thing.release();
}
