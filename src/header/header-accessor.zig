const bm = @import("./body-meta.zig");
const cm = @import("context-meta.zig");

pub const HeaderAccessor = struct {
    body_meta: bm.BodyMeta,
    context_meta: ?cm.ContextMeta,

    message_len: []u8, // (1-2) bytes
    message_num: []u8, // (0-3) bytes
    object: []u8, // (0-3) bytes
    method: []u8, // (0-1) byte
    session: []u8, // (0-3) bytes
    process: []u8, // (0-16) bytes
    header_len: usize,

    pub fn get_message_len(self: HeaderAccessor) u16 {
        // Use compact version with direct @as for 2 bytes
        if (self.message_len.len == 2) {
            return @as(u16, self.message_len[0]) << 8 | self.message_len[1];
        }
        return self.message_len[0];
    }

    pub fn get_message_num(self: HeaderAccessor) u32 {
        // Use switch for optimal strategy for each length
        return switch (self.message_num.len) {
            0 => 0,
            1 => self.message_num[0],
            2 => @as(u32, self.message_num[0]) << 8 | self.message_num[1],
            3 => @as(u32, self.message_num[0]) << 16 |
                @as(u32, self.message_num[1]) << 8 |
                self.message_num[2],
            else => unreachable,
        };
    }

    pub fn get_object(self: HeaderAccessor) u32 {
        return switch (self.object.len) {
            0 => 0,
            1 => self.object[0],
            2 => @as(u32, self.object[0]) << 8 | self.object[1],
            3 => @as(u32, self.object[0]) << 16 |
                @as(u32, self.object[1]) << 8 |
                self.object[2],
            else => unreachable,
        };
    }

    pub fn get_session(self: HeaderAccessor) u32 {
        return switch (self.session.len) {
            0 => 0,
            1 => self.session[0],
            2 => @as(u32, self.session[0]) << 8 | self.session[1],
            3 => @as(u32, self.session[0]) << 16 |
                @as(u32, self.session[1]) << 8 |
                self.session[2],
            else => unreachable,
        };
    }

    pub fn get_process(self: HeaderAccessor) []const u8 {
        return self.process;
    }

    pub fn set_message_len(self: *HeaderAccessor, value: u16) void {
        switch (self.message_len.len) {
            1 => self.message_len[0] = @truncate(value),
            2 => {
                self.message_len[0] = @truncate(value >> 8);
                self.message_len[1] = @truncate(value);
            },
            else => unreachable,
        }
    }

    pub fn set_message_num(self: *HeaderAccessor, value: u32) void {
        switch (self.message_num.len) {
            0 => {},
            1 => self.message_num[0] = @truncate(value),
            2 => {
                self.message_num[0] = @truncate(value >> 8);
                self.message_num[1] = @truncate(value);
            },
            3 => {
                self.message_num[0] = @truncate(value >> 16);
                self.message_num[1] = @truncate(value >> 8);
                self.message_num[2] = @truncate(value);
            },
            else => unreachable,
        }
    }

    pub fn set_object(self: *HeaderAccessor, value: u32) void {
        switch (self.object.len) {
            0 => {},
            1 => self.object[0] = @truncate(value),
            2 => {
                self.object[0] = @truncate(value >> 8);
                self.object[1] = @truncate(value);
            },
            3 => {
                self.object[0] = @truncate(value >> 16);
                self.object[1] = @truncate(value >> 8);
                self.object[2] = @truncate(value);
            },
            else => unreachable,
        }
    }

    pub fn get_method(self: HeaderAccessor) ?u8 {
        return switch (self.method.len) {
            0 => null,
            1 => self.method[0],
            else => unreachable,
        };
    }

    pub fn set_method(self: *HeaderAccessor, value: ?u8) void {
        switch (self.method.len) {
            0 => {},
            1 => {
                if (value) |v| self.method[0] = v else {}
            },
            else => unreachable,
        }
    }

    pub fn set_session(self: *HeaderAccessor, value: u32) void {
        switch (self.session.len) {
            0 => {},
            1 => self.session[0] = @truncate(value),
            2 => {
                self.session[0] = @truncate(value >> 8);
                self.session[1] = @truncate(value);
            },
            3 => {
                self.session[0] = @truncate(value >> 16);
                self.session[1] = @truncate(value >> 8);
                self.session[2] = @truncate(value);
            },
            else => unreachable,
        }
    }

    pub fn read(package: []const u8) !HeaderAccessor {
        const body_meta = try bm.BodyMeta.parse(package[0]);
        var context_meta: ?cm.ContextMeta = null;

        if (body_meta.next_meta_byte) {
            context_meta = try cm.ContextMeta.parse(package[1]);
        }

        return scan(package, body_meta, context_meta);
    }

    pub fn build(package: []u8, body_meta: bm.BodyMeta, context_meta: ?cm.ContextMeta) !HeaderAccessor {
        package[0] = body_meta.build();

        if (body_meta.next_meta_byte) {
            if (context_meta) |ctx_meta| {
                package[1] = ctx_meta.build();
            } else {
                return error.MissingContextMeta;
            }
        }

        return scan(package, body_meta, context_meta);
    }
    pub fn scan(package: []const u8, body_meta: bm.BodyMeta, context_meta: ?cm.ContextMeta) !HeaderAccessor {
        // Вычисляем позицию начала данных после метаданных
        var pos: usize = if (body_meta.next_meta_byte) 2 else 1;

        // Определяем размер поля длины сообщения
        const message_len_size: usize = if (body_meta.message_len_duble) 2 else 1;

        // Изменяемый пустой массив для использования в пустых срезах
        var empty_array = [_]u8{};

        // Для каждого поля выполняем @constCast, чтобы удалить const квалификатор
        const message_len = @constCast(package[pos .. pos + message_len_size]);
        pos += message_len_size;

        // message_num
        const message_num = if (body_meta.message_num_len > 0)
            @constCast(package[pos .. pos + body_meta.message_num_len])
        else
            &empty_array;
        pos += body_meta.message_num_len;

        // object
        const object = if (body_meta.object_len > 0)
            @constCast(package[pos .. pos + body_meta.object_len])
        else
            &empty_array;
        pos += body_meta.object_len;

        // method
        const method = if (body_meta.method_len)
            @constCast(package[pos .. pos + 1])
        else
            &empty_array;
        pos += if (body_meta.method_len) 1 else 0;

        // Инициализация session и process пустыми изменяемыми срезами
        var session: []u8 = &empty_array;
        var process: []u8 = &empty_array;

        if (context_meta) |ctx_meta| {
            // Для session
            if (ctx_meta.session_len > 0) {
                session = @constCast(package[pos .. pos + ctx_meta.session_len]);
            }
            pos += ctx_meta.session_len;

            // Для process
            if (ctx_meta.process_len > 0) {
                process = @constCast(package[pos .. pos + ctx_meta.process_len]);
            }
            pos += ctx_meta.process_len;
        }

        // Корректировка для соответствия ожиданиям протокола
        // Для случая с context_meta добавляем 1 байт, а для случая без - вычитаем 1 байт
        const header_len = pos;

        return HeaderAccessor{
            .body_meta = body_meta,
            .context_meta = context_meta,
            .message_len = message_len,
            .message_num = message_num,
            .object = object,
            .method = method,
            .session = session,
            .process = process,
            .header_len = header_len,
        };
    }
};

test "HeaderAccessor parse test with complete meta" {
    const std = @import("std");
    const testing = std.testing;

    // Create test data with both body meta and context meta
    // body_meta: message_len_duble=true, next_flag=false, message_num_len=2, object_len=1, method_len=true, next_meta_byte=true
    // context_meta: session_len=1, process_len=2, next_meta_byte=false
    var test_data = [_]u8{
        0b10100111, // body meta byte (0xA7)
        0b01000100, // context meta byte (0x44)
        0x00, 0x0C, // message length (12 bytes total)
        0x12, 0x34, // message_num (0x1234)
        0x56, // object (0x56)
        0x78, // method (0x78)
        0x9A, // session (0x9A)
        0xBC, 0xDE, // process (0xBCDE)
    };

    const header_accessor = try HeaderAccessor.read(&test_data);

    // Test body_meta fields
    try testing.expect(header_accessor.body_meta.message_len_duble);
    try testing.expect(!header_accessor.body_meta.next_flag);
    try testing.expectEqual(@as(u8, 2), header_accessor.body_meta.message_num_len);
    try testing.expectEqual(@as(u8, 1), header_accessor.body_meta.object_len);
    try testing.expect(header_accessor.body_meta.method_len);
    try testing.expect(header_accessor.body_meta.next_meta_byte);

    // Test context_meta fields
    try testing.expect(header_accessor.context_meta != null);
    if (header_accessor.context_meta) |ctx_meta| {
        try testing.expectEqual(@as(u8, 1), ctx_meta.session_len);
        try testing.expectEqual(@as(u8, 2), ctx_meta.process_len);
        try testing.expect(!ctx_meta.next_meta_byte);
    }

    // Test accessor functions
    try testing.expectEqual(@as(u16, 0x000C), header_accessor.get_message_len());
    try testing.expectEqual(@as(u32, 0x1234), header_accessor.get_message_num());
    try testing.expectEqual(@as(u32, 0x56), header_accessor.get_object());
    try testing.expectEqual(@as(?u8, 0x78), header_accessor.get_method());
    try testing.expectEqual(@as(u32, 0x9A), header_accessor.get_session());
    try testing.expectEqualSlices(u8, &[_]u8{ 0xBC, 0xDE }, header_accessor.get_process());

    // Test header length calculation
    try testing.expectEqual(@as(usize, 11), header_accessor.header_len);
}

test "HeaderAccessor parse test without context meta" {
    const std = @import("std");
    const testing = std.testing;

    // Create test data with only body meta (no context meta)
    // body_meta: message_len_duble=false, next_flag=true, message_num_len=1, object_len=2, method_len=true, next_meta_byte=false
    var test_data = [_]u8{
        0b01011010, // body meta byte (0x5A)
        0x0A, // message length (10 bytes total)
        0x12, // message_num (0x12)
        0x34, 0x56, // object (0x3456)
        0x78, // method (0x78)
        0x00,
        0x00,
        0x00,
        0x00,
        0x00, // padding to ensure we don't read off the end
    };

    const header_accessor = try HeaderAccessor.read(&test_data);

    // Test body_meta fields
    try testing.expect(!header_accessor.body_meta.message_len_duble);
    try testing.expect(header_accessor.body_meta.next_flag);
    try testing.expectEqual(@as(u8, 1), header_accessor.body_meta.message_num_len);
    try testing.expectEqual(@as(u8, 2), header_accessor.body_meta.object_len);
    try testing.expect(header_accessor.body_meta.method_len);
    try testing.expect(!header_accessor.body_meta.next_meta_byte);

    // Test context_meta is null
    try testing.expectEqual(header_accessor.context_meta, null);

    // Test accessor functions
    try testing.expectEqual(@as(u16, 0x0A), header_accessor.get_message_len());
    try testing.expectEqual(@as(u32, 0x12), header_accessor.get_message_num());
    try testing.expectEqual(@as(u32, 0x3456), header_accessor.get_object());
    try testing.expectEqual(@as(?u8, 0x78), header_accessor.get_method());
    try testing.expectEqual(@as(u32, 0), header_accessor.get_session()); // Session should be 0 when not present
    try testing.expectEqual(@as(usize, 0), header_accessor.get_process().len); // Process should be empty when not present

    // Test header length calculation
    try testing.expectEqual(@as(usize, 6), header_accessor.header_len);
}

test "HeaderAccessor build and read test" {
    const std = @import("std");
    const testing = std.testing;

    var buffer: [16]u8 = undefined;

    // Create body_meta and context_meta
    const body_meta = bm.BodyMeta{
        .message_len_duble = true,
        .next_flag = true,
        .message_num_len = 2,
        .object_len = 1,
        .method_len = true,
        .next_meta_byte = true,
    };

    const context_meta = cm.ContextMeta{
        .session_len = 2,
        .process_len = 3,
        .next_meta_byte = false,
    };

    // Build the header
    var built_header = try HeaderAccessor.build(&buffer, body_meta, context_meta);

    // Set values
    built_header.set_message_len(0x0123);
    built_header.set_message_num(0xABCD);
    built_header.set_object(0xEF);
    built_header.set_method(0x99);
    built_header.set_session(0x4567);

    // Read it back
    const read_header = try HeaderAccessor.read(&buffer);

    // Test that values were preserved
    try testing.expectEqual(body_meta, read_header.body_meta);
    try testing.expect(read_header.context_meta != null);
    if (read_header.context_meta) |ctx_meta| {
        try testing.expectEqual(context_meta.session_len, ctx_meta.session_len);
        try testing.expectEqual(context_meta.process_len, ctx_meta.process_len);
        try testing.expectEqual(context_meta.next_meta_byte, ctx_meta.next_meta_byte);
    }

    try testing.expectEqual(@as(u16, 0x0123), read_header.get_message_len());
    try testing.expectEqual(@as(u32, 0xABCD), read_header.get_message_num());
    try testing.expectEqual(@as(u32, 0xEF), read_header.get_object());
    try testing.expectEqual(@as(?u8, 0x99), read_header.get_method());
    try testing.expectEqual(@as(u32, 0x4567), read_header.get_session());
}
