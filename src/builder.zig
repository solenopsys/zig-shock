const std = @import("std");

const bm = @import("header/body-meta.zig");
const cm = @import("header/context-meta.zig");
const ha = @import("header/header-accessor.zig");

const SHOCKPackageParser = @import("parser.zig").SHOCKPackageParser;

pub const SHOCKPackageBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SHOCKPackageBuilder {
        return SHOCKPackageBuilder{
            .allocator = allocator,
        };
    }

    pub fn build_into(self: *SHOCKPackageBuilder, buffer: []u8, body: []const u8, message_num: ?u32, object: ?u32, method: ?u8, session: ?u32, process: ?[]const u8) !usize {
        _ = self;
        // Determine required sizes for all fields
        const message_num_len: u8 = if (message_num) |num| blk: {
            if (num <= 0xFF) break :blk 1;
            if (num <= 0xFFFF) break :blk 2;
            break :blk 3;
        } else 0;

        const object_len: u8 = if (object) |obj| blk: {
            if (obj <= 0xFF) break :blk 1;
            if (obj <= 0xFFFF) break :blk 2;
            break :blk 3;
        } else 0;

        const method_len: bool = method != null;

        var needs_context_meta = false;
        var session_len: u8 = 0;
        var process_len: u8 = 0;

        if (session != null or process != null) {
            needs_context_meta = true;

            session_len = if (session) |sess| blk: {
                if (sess <= 0xFF) break :blk 1;
                if (sess <= 0xFFFF) break :blk 2;
                break :blk 3;
            } else 0;

            process_len = if (process) |proc|
                @intCast(@min(proc.len, 16))
            else
                0;
        }

        // Calculate total message length (header + body)
        const meta_bytes_len: usize = if (needs_context_meta) 2 else 1;
        const message_len_size: usize = if (body.len > 0xFF) 2 else 1;

        const method_size: usize = if (method_len) 1 else 0;
        const header_len = meta_bytes_len + message_len_size + message_num_len +
            object_len + method_size +
            session_len + process_len;

        const total_len = header_len + body.len;

        // Check if buffer is large enough
        if (buffer.len < total_len) {
            return error.BufferTooSmall;
        }

        // Create body_meta
        const body_meta = bm.BodyMeta{
            .message_len_duble = message_len_size == 2,
            .next_flag = false, // Can be set based on requirements
            .message_num_len = message_num_len,
            .object_len = object_len,
            .method_len = method_len,
            .next_meta_byte = needs_context_meta,
        };

        // Create context_meta if needed
        var context_meta: ?cm.ContextMeta = null;
        if (needs_context_meta) {
            context_meta = cm.ContextMeta{
                .session_len = session_len,
                .process_len = process_len,
                .next_meta_byte = false, // Reserved bit, currently not used
            };
        }

        // Fill the meta bytes
        buffer[0] = body_meta.build();
        if (needs_context_meta) {
            buffer[1] = context_meta.?.build();
        }

        // Create header accessor
        var header_accessor = try ha.HeaderAccessor.scan(buffer, body_meta, context_meta);

        // Set the actual values for each field
        header_accessor.set_message_len(@intCast(total_len));

        if (message_num) |num| {
            header_accessor.set_message_num(num);
        }

        if (object) |obj| {
            header_accessor.set_object(obj);
        }

        if (method) |meth| {
            header_accessor.set_method(meth);
        }

        if (session) |sess| {
            header_accessor.set_session(sess);
        }

        // Copy the process bytes if any
        if (process) |proc| {
            for (0..process_len) |i| {
                buffer[header_accessor.header_len - process_len + i] = proc[i];
            }
        }

        // Copy the body
        std.mem.copyForwards(u8, buffer[header_len .. header_len + body.len], body);

        return total_len;
    }

    // Вспомогательная функция для создания пакета с выделением памяти
    // (оставлена для обратной совместимости)
    pub fn build(self: *SHOCKPackageBuilder, body: []const u8, message_num: ?u32, object: ?u32, method: ?u8, session: ?u32, process: ?[]const u8) ![]u8 {
        // Предварительный расчет размера пакета для выделения буфера
        const process_len = if (process) |proc| @min(proc.len, 16) else 0;
        const needs_context_meta = session != null or process != null;
        const meta_bytes_len = if (needs_context_meta) 2 else 1;
        const message_len_size = if (body.len > 0xFF) 2 else 1;

        // Расчет размера для предварительного выделения памяти
        // Используем максимально возможные размеры полей для упрощения
        const max_header_size = meta_bytes_len + message_len_size + 3 + 3 + 1 + 3 + process_len;
        const total_len = max_header_size + body.len;

        // Выделяем буфер с запасом
        var buffer = try self.allocator.alloc(u8, total_len);
        errdefer self.allocator.free(buffer);

        // Используем оптимизированный метод build_into
        const actual_len = try self.build_into(buffer, body, message_num, object, method, session, process);

        // Если размер фактически заполненного буфера меньше выделенного,
        // можно было бы изменить его размер, но для эффективности не делаем это

        return buffer[0..actual_len];
    }
};

test "SHOCKPackageBuilder build test" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var builder = SHOCKPackageBuilder.init(allocator);

    const body = [_]u8{ 0x01, 0x02, 0x03 };
    const process_data = [_]u8{ 0xBC, 0xDE };

    // Выделяем буфер с запасом
    var buffer: [64]u8 = undefined;

    const pkg_len = try builder.build_into(&buffer, &body, 0x1234, 0x56, 0x78, 0x9A, &process_data);

    // Создаем срез буфера только с действительными данными
    const package = buffer[0..pkg_len];

    // Parse the package to verify it was built correctly
    const pkg = try SHOCKPackageParser.parse(package);

    // Verify parsed values
    try testing.expect(pkg.body_meta.message_len_duble == false);
    try testing.expect(!pkg.body_meta.next_flag);
    try testing.expectEqual(@as(u8, 2), pkg.body_meta.message_num_len);
    try testing.expectEqual(@as(u8, 1), pkg.body_meta.object_len);
    try testing.expect(pkg.body_meta.method_len);
    try testing.expect(pkg.body_meta.next_meta_byte);

    try testing.expect(pkg.context_meta != null);
    if (pkg.context_meta) |ctx_meta| {
        try testing.expectEqual(@as(u8, 1), ctx_meta.session_len);
        try testing.expectEqual(@as(u8, 2), ctx_meta.process_len);
    }

    try testing.expectEqual(@as(u32, 0x1234), pkg.header_accessor.get_message_num());
    try testing.expectEqual(@as(u32, 0x56), pkg.header_accessor.get_object());
    try testing.expectEqual(@as(?u8, 0x78), pkg.header_accessor.get_method());
    try testing.expectEqual(@as(u32, 0x9A), pkg.header_accessor.get_session());

    try testing.expectEqualSlices(u8, &body, pkg.body);
}

test "SHOCKPackageBuilder without context meta" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var builder = SHOCKPackageBuilder.init(allocator);

    const body = [_]u8{ 0x01, 0x02, 0x03 };

    // Используем буфер на стеке
    var buffer: [32]u8 = undefined;

    const pkg_len = try builder.build_into(&buffer, &body, 0x1234, 0x56, 0x78, null, null);

    const package = buffer[0..pkg_len];

    // Parse the package to verify it was built correctly
    const pkg = try SHOCKPackageParser.parse(package);

    // Verify parsed values
    try testing.expect(!pkg.body_meta.next_meta_byte); // No context meta
    try testing.expectEqual(@as(u8, 2), pkg.body_meta.message_num_len);
    try testing.expectEqual(@as(u8, 1), pkg.body_meta.object_len);
    try testing.expect(pkg.body_meta.method_len);

    try testing.expectEqual(pkg.context_meta, null);

    try testing.expectEqual(@as(u32, 0x1234), pkg.header_accessor.get_message_num());
    try testing.expectEqual(@as(u32, 0x56), pkg.header_accessor.get_object());
    try testing.expectEqual(@as(?u8, 0x78), pkg.header_accessor.get_method());

    try testing.expectEqualSlices(u8, &body, pkg.body);
}
