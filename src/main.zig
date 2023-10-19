const std = @import("std");
const Dt = @import("dt.zig").Dt;
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var dt = try Dt.init(gpa.allocator());

    while (true) {
        dt.readln() catch |e| switch (e) {
            error.EndOfStream => return,
            else => return e,
        };
        try dt.status();
    }
}

test "include others" {
    std.testing.refAllDeclsRecursive(@This());
}
