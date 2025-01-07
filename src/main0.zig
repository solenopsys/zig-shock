const std = @import("std");

const SHOCKPackage = struct {
    process_len: u8,
    object_len: u8,
    method_len: u8,
    process: []const u8,
    object: []const u8,
    method: []const u8,
    body: []const u8,

    pub fn parse(data: []const u8) !SHOCKPackage {
        const header = data[0];
        const process_len: u8 = (header >> 3) & 0b11111; // 5 bits
        const object_len: u8 = (header >> 1) & 0b11; // 2 bits
        const method_len: u8 = header & 0b1; // 1 bit

        var offset: usize = 1;
        const process = data[offset .. offset + process_len];
        offset += process_len;
        const object = data[offset .. offset + object_len];
        offset += object_len;
        const method = data[offset .. offset + method_len];
        offset += method_len;
        const body = data[offset..data.len];

        return SHOCKPackage{
            .process_len = process_len,
            .object_len = object_len,
            .method_len = method_len,
            .process = process,
            .object = object,
            .method = method,
            .body = body,
        };
    }
};

pub fn main() !void {
    // hw
    var test_data: [11]u8 = [_]u8{ 0b00010101, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10 }; // header: 5-bit process, 2-bit object, 1-bit method

    const start = std.time.milliTimestamp();

    const count = 1000000000;

    for (0..count) |_| {
        const pkg = try SHOCKPackage.parse(test_data[0..]);
        _ = pkg;
    }
    const end = std.time.milliTimestamp();

    std.debug.print("Time ms: {d}\n", .{end - start});
}

test "parce test" {
    // process 2
    // object 1
    // method 1
    var test_data: [11]u8 = [_]u8{ 0b00010101, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x10 }; // header: 5-bit process, 2-bit object, 1-bit method

    const pkg = try SHOCKPackage.parse(test_data[0..]);

    std.debug.print("Process: {d}\n", .{pkg.process_len});
    try std.testing.expect(pkg.process_len == 2); // Заголовок определяет длину 5 байт для process
    try std.testing.expect(pkg.object_len == 2); // Заголовок определяет длину 2 байта для object
    try std.testing.expect(pkg.method_len == 1); // Заголовок определяет длину 1 байт для method

    try std.testing.expectEqualSlices(u8, pkg.process, &[_]u8{
        0x01,
        0x02,
    });
    try std.testing.expectEqualSlices(u8, pkg.object, &[_]u8{ 0x03, 0x04 });
    try std.testing.expectEqualSlices(u8, pkg.method, &[_]u8{0x05});

    try std.testing.expectEqualSlices(u8, pkg.body, &[_]u8{ 0x06, 0x07, 0x08, 0x09, 0x10 });
}
