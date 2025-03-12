const std = @import("std");
const bm = @import("header/body-meta.zig");
const cm = @import("header/context-meta.zig");
const ha = @import("header/header-accessor.zig");

pub const SHOCKPackage = struct {
    body_meta: bm.BodyMeta,
    context_meta: ?cm.ContextMeta,
    header_accessor: ha.HeaderAccessor,
    body: []const u8,
    header_len: usize,
    total_len: usize,
};

pub const SHOCKPackageParser = struct {
    pub fn parse(data: []const u8) !SHOCKPackage {
        const header_accessor = try ha.HeaderAccessor.read(data);
        const header_len = header_accessor.header_len;

        // Get message length from the accessor
        const message_len = header_accessor.get_message_len();

        // Body is everything between the header and the end of the message
        const body = data[header_len..message_len];

        return SHOCKPackage{
            .body_meta = header_accessor.body_meta,
            .context_meta = header_accessor.context_meta,
            .header_accessor = header_accessor,
            .body = body,
            .header_len = header_len,
            .total_len = message_len,
        };
    }
};

test "SHOCKPackageParser parse test" {
    const testing = std.testing;

    // Create test data based on the new header structure
    // Bits of first byte:
    // message_len_duble: true (bit 7)
    // next_flag: false (bit 6)
    // message_num_len: 2 (bits 5-4)
    // object_len: 1 (bits 3-2)
    // method_len: true (bit 1)
    // next_meta_byte: true (bit 0)
    // = 10100111 = 0xA7

    // Bits of second byte:
    // session_len: 1 (bits 7-6)
    // process_len: 2 (bits 5-1)
    // reserved: false (bit 0)
    // = 01000100 = 0x44

    var test_data = [_]u8{
        0xA7, // body meta byte
        0x44, // context meta byte
        0x00, 0x0F, // message length: 15 bytes total
        0x12, 0x34, // message_num: 0x1234
        0x56, // object: 0x56
        0x78, // method: 0x78
        0x9A, // session: 0x9A
        0xBC, 0xDE, // process: 0xBCDE
        0x01, 0x02,
        0x03, // body
    };

    const pkg = try SHOCKPackageParser.parse(&test_data);

    // Verify parsed values
    try testing.expect(pkg.body_meta.message_len_duble);
    try testing.expect(!pkg.body_meta.next_flag);
    try testing.expectEqual(@as(u8, 2), pkg.body_meta.message_num_len);
    try testing.expectEqual(@as(u8, 1), pkg.body_meta.object_len);
    try testing.expect(pkg.body_meta.method_len);
    try testing.expect(pkg.body_meta.next_meta_byte);

    try testing.expect(pkg.context_meta != null);
    if (pkg.context_meta) |ctx_meta| {
        try testing.expectEqual(@as(u8, 1), ctx_meta.session_len);
        try testing.expectEqual(@as(u8, 2), ctx_meta.process_len);
        try testing.expect(!ctx_meta.next_meta_byte);
    }

    try testing.expectEqual(@as(u16, 0x000F), pkg.header_accessor.get_message_len());
    try testing.expectEqual(@as(u32, 0x1234), pkg.header_accessor.get_message_num());
    try testing.expectEqual(@as(u32, 0x56), pkg.header_accessor.get_object());
    try testing.expectEqual(@as(?u8, 0x78), pkg.header_accessor.get_method());
    try testing.expectEqual(@as(u32, 0x9A), pkg.header_accessor.get_session());

    try testing.expectEqual(@as(usize, 12), pkg.header_len);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02, 0x03 }, pkg.body);
}
