const std = @import("std");
const Allocator = std.mem.Allocator;

const Dictionary = @import("types.zig").Dictionary;

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

/// A reference-counted thing.
pub fn Rc(comptime IT: type) type {
    return struct {
        allocator: Allocator,
        it: IT,
        refs: *usize,

        const Self = @This();

        pub fn new(allocator: Allocator) !Self {
            const it = if (comptime std.meta.trait.hasFn("init")(IT))
                IT.init(allocator)
            else if (comptime std.meta.trait.hasFn("new")(IT))
                try IT.new(allocator)
            else
                undefined;
            const refs = try allocator.create(usize);
            refs.* = 1;
            return .{
                .allocator = allocator,
                .it = it,
                .refs = refs,
            };
        }

        /// Creates a new reference.
        pub fn newref(self: Self) Self {
            self.refs.* += 1;
            return .{
                .allocator = self.allocator,
                .it = self.it,
                .refs = self.refs,
            };
        }

        /// Creates a clone, allocating a new copy of "it."
        pub fn clone(self: *Self) !Self {
            var theClone = try Self.new(self.allocator);

            if (IT == Dictionary) {
                var entries = self.it.iterator();
                while (entries.next()) |entry| {
                    try theClone.it.put(entry.key_ptr.newref(), entry.value_ptr.newref());
                }
                return theClone;
            }

            try theClone.it.ensureTotalCapacity(self.it.items);

            if (canClone(IT)) {
                for (self.it.items) |item| {
                    try theClone.it.append(item.clone());
                }
            } else {
                try theClone.it.appendSlice(self.it.items);
            }

            return theClone;
        }

        /// Releases this reference. If this was the final reference, the
        /// it and the counter are freed.
        pub fn release(self: Self) void {
            self.refs.* -= 1;
            if (self.refs.* == 0) {
                free(self.it);
                self.allocator.destroy(self.refs);
            }
        }
    };
}
