pub const BodyMeta = packed struct {
    message_len_duble: bool,
    next_flag: bool,
    message_num_len: u8,
    object_len: u8,
    method_len: bool,
    next_meta_byte: bool,

    pub fn parse(meta: u8) !BodyMeta {
        const second_byte_flag = (meta & 0b0000_0001) != 0;
        const message_len_duble = (meta & 0b1000_0000) != 0;
        const next_flag = (meta & 0b0100_0000) != 0;
        const message_num_len = @as(u8, (meta & 0b0011_0000) >> 4);
        const object_len = @as(u8, (meta & 0b0000_1100) >> 2);
        const method_len = (meta & 0b0000_0010) != 0;

        return BodyMeta{
            .message_len_duble = message_len_duble,
            .next_flag = next_flag,
            .message_num_len = message_num_len,
            .object_len = object_len,
            .method_len = method_len,
            .next_meta_byte = second_byte_flag,
        };
    }

    pub fn build(self: BodyMeta) u8 {
        var meta: u8 = 0;

        if (self.message_len_duble) meta |= 0b1000_0000;
        if (self.next_flag) meta |= 0b0100_0000;
        meta |= (self.message_num_len & 0b11) << 4;
        meta |= (self.object_len & 0b11) << 2;
        if (self.method_len) meta |= 0b0000_0010;
        if (self.next_meta_byte) meta |= 0b0000_0001;

        return meta;
    }
};
test "BodyMetaHeader write and parse" {
    const std = @import("std");
    const testing = std.testing;

    const body_meta = BodyMeta{
        .message_len_duble = true,
        .next_flag = false,
        .message_num_len = 2,
        .object_len = 1,
        .method_len = true,
        .next_meta_byte = false,
    };

    const meta = body_meta.build();

    const parsed = try BodyMeta.parse(meta);

    try testing.expect(parsed.message_len_duble);
    try testing.expect(!parsed.next_flag);
    try testing.expectEqual(@as(u8, 2), parsed.message_num_len);
    try testing.expectEqual(@as(u8, 1), parsed.object_len);
    try testing.expect(parsed.method_len);
    try testing.expect(!parsed.next_meta_byte);

    try testing.expectEqual(body_meta, parsed);

    std.debug.print("\nMeta byte: 0b{b:0>8}\n", .{meta});
}

test "BodyMetaHeader write and parse with opposite values" {
    const std = @import("std");
    const testing = std.testing;

    const body_meta = BodyMeta{
        .message_len_duble = false,
        .next_flag = true,
        .message_num_len = 3,
        .object_len = 2,
        .method_len = false,
        .next_meta_byte = true,
    };

    const meta = body_meta.build();

    const parsed = try BodyMeta.parse(meta);

    try testing.expect(!parsed.message_len_duble);
    try testing.expect(parsed.next_flag);
    try testing.expectEqual(@as(u8, 3), parsed.message_num_len);
    try testing.expectEqual(@as(u8, 2), parsed.object_len);
    try testing.expect(!parsed.method_len);
    try testing.expect(parsed.next_meta_byte);

    try testing.expectEqual(body_meta, parsed);

    std.debug.print("\nTest 2 meta byte: 0b{b:0>8}\n", .{meta});
}
