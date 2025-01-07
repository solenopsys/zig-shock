const std = @import("std");
const bm = @import("body-meta.zig");
const cm = @import("context-meta.zig");

const SHOCKPackageParser = struct {
  
    body: []const u8,
    packet_len: u16,
    header_len: usize,

    pub fn parse(data: []const u8) !SHOCKPackageParser {
        const body_meta = try bm.BodyMetaParser.parse(data[0]);
        var header_len = body_meta.len();
        const packet_len = @as(u16, @bitCast([2]u8{ data[4], data[3] })); //todo

        var context_meta: ?cm.ContextMetaParser = null;

        if (body_meta.second_byte_flag) {
            context_meta = try cm.ContextMetaParser.parse(data[1]);
            header_len += context_meta.?.len();
        }

        std.debug.print("Header len: {d}\n", .{header_len});
        std.debug.print("Packet len: {d}\n", .{packet_len});

        const body = data[header_len..packet_len];

        return SHOCKPackageParser{
            .body_meta = body_meta,
            .context_meta = context_meta,
            .body = body,
            .packet_len = packet_len,
            .header_len = header_len,
        };
    }
};

const SHOCKPackageBuilder = struct {
    pub fn link( body: []const u8) SHOCKPackageBuilder {
        return SHOCKPackageBuilder{
            .body = body,
        };
    }
}

test "parse test" {
    const testing = std.testing;

    // message_len_duble: true, next_flag: true, message_num_len: 0, object_len: 3, method_len: true, second_byte_flag: true
    var test_data = [_]u8{
        0b1100_1111, // body meta byte
        0b1000_0010, // context meta byte
        0x01, 0x02, // message length bytes
        0x03, 0x04, // object bytes
        0x05, // method byte
        0x06,
        0x07,
        0x08, // body bytes
    };

    const pkg = try SHOCKPackageParser.parse(&test_data);

    // Проверяем основные поля body_meta
    try testing.expect(pkg.body_meta.message_len_duble);
    try testing.expect(pkg.body_meta.next_flag);
    try testing.expectEqual(@as(u8, 0), pkg.body_meta.message_num_len);
    try testing.expectEqual(@as(u8, 3), pkg.body_meta.object_len);
    try testing.expect(pkg.body_meta.method_len);
    try testing.expect(pkg.body_meta.second_byte_flag);

    // Проверяем наличие и значения context_meta
    try testing.expect(pkg.context_meta != null);
    if (pkg.context_meta) |ctx_meta| {
        try testing.expectEqual(@as(u8, 2), ctx_meta.session_len);
        try testing.expectEqual(@as(u8, 2), ctx_meta.process_len);
    }

    // Проверяем длину пакета и заголовка
    try testing.expectEqual(@as(u16, 0x0203), pkg.packet_len);
    try testing.expectEqual(@as(usize, 7), pkg.header_len); // 1 (meta) + 1 (context) + 2 (length) + 3 (object, method)

    // Проверяем содержимое тела
    try testing.expectEqualSlices(u8, &[_]u8{ 0x06, 0x07, 0x08 }, pkg.body);
}
