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

    pub fn build(self: *SHOCKPackageBuilder, body: []const u8, message_num: ?u32, object: ?u32, method: ?u8, session: ?u32, process: ?[]const u8) ![]u8 {
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

        // Allocate the full package buffer
        var package = try self.allocator.alloc(u8, total_len);
        errdefer self.allocator.free(package);

        // Fill the meta bytes
        package[0] = body_meta.build();
        if (needs_context_meta) {
            package[1] = context_meta.?.build();
        }

        // Create header accessor
        var header_accessor = try ha.HeaderAccessor.scan(package, body_meta, context_meta);

        // Set the actual values for each field
        if (message_len_size == 2) {
            header_accessor.set_message_len(@intCast(total_len));
        } else {
            header_accessor.set_message_len(@intCast(total_len));
        }

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
                package[header_accessor.header_len - process_len + i] = proc[i];
            }
        }

        // Copy the body
        std.mem.copyForwards(u8, package[header_len..], body);

        return package;
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

    const package = try builder.build(&body, // body
        0x1234, // message_num
        0x56, // object
        0x78, // method
        0x9A, // session
        &process_data // process
    );

    // Parse the package to verify it was built correctly
    const pkg = try SHOCKPackageParser.parse(package);

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

    const package = try builder.build(&body, // body
        0x1234, // message_num
        0x56, // object
        0x78, // method
        null, // session (null means no context meta)
        null // process (null means no context meta)
    );

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
