const std = @import("std");

pub const canClone = std.meta.trait.hasFn("clone");

pub fn free(something: anytype) void {
    const T = @TypeOf(something);
    var thing = something;

    // Pointers
    if (comptime std.meta.trait.isSingleItemPtr(T)) return free(thing.*);

    // "Primitives"
    if (!comptime std.meta.trait.isContainer(T)) return;

    // ArrayList
    if (comptime @hasField(T, "items")) for (thing.items) |item| free(item);

    // HashMap
    if (comptime @hasDecl(T, "keyIterator")) {
        var it = thing.keyIterator();
        while (it.next()) |key| free(key);
    }
    if (comptime @hasDecl(T, "valueIterator")) {
        var it = thing.valueIterator();
        while (it.next()) |value| free(value);
    }

    // Many things
    if (comptime @hasDecl(T, "deinit")) thing.deinit();

    // Rc
    if (comptime @hasDecl(T, "release")) thing.release();
}
