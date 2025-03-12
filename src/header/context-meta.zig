pub const ContextMeta = packed struct {
    session_len: u8,
    process_len: u8,
    next_meta_byte: bool, // for extension protocol

    pub fn parse(b: u8) !ContextMeta {
        const session_len = @as(u8, (b & 0b1100_0000) >> 6);
        const process_len = @as(u8, (b & 0b0011_1110) >> 1);
        const custom = (b & 0b0000_0001) != 0;

        return ContextMeta{
            .session_len = session_len,
            .process_len = process_len,
            .next_meta_byte = custom,
        };
    }

    pub fn build(self: ContextMeta) u8 {
        var meta: u8 = 0;

        meta |= (self.session_len & 0b11) << 6;
        meta |= (self.process_len & 0b11111) << 1;
        if (self.next_meta_byte) meta |= 0b0000_0001;

        return meta;
    }
};

test "ContextMeta write and parse" {
    const std = @import("std");
    const testing = std.testing;

    const context_meta = ContextMeta{
        .session_len = 2,
        .process_len = 15,
        .next_meta_byte = true,
    };

    const meta = context_meta.build();

    const parsed = try ContextMeta.parse(meta);

    try testing.expectEqual(@as(u8, 2), parsed.session_len);
    try testing.expectEqual(@as(u8, 15), parsed.process_len);
    try testing.expect(parsed.next_meta_byte);

    try testing.expectEqual(context_meta, parsed);

    std.debug.print("\nMeta byte: 0b{b:0>8}\n", .{meta});
}

test "ContextMeta write and parse with different values" {
    const std = @import("std");
    const testing = std.testing;

    const context_meta = ContextMeta{
        .session_len = 3,
        .process_len = 10,
        .next_meta_byte = false,
    };

    const meta = context_meta.build();

    const parsed = try ContextMeta.parse(meta);

    try testing.expectEqual(@as(u8, 3), parsed.session_len);
    try testing.expectEqual(@as(u8, 10), parsed.process_len);
    try testing.expect(!parsed.next_meta_byte);

    try testing.expectEqual(context_meta, parsed);

    std.debug.print("\nTest 2 meta byte: 0b{b:0>8}\n", .{meta});
}
