const bm = @import("./body-meta.zig");
const cm = @import("context-meta.zig");

pub const HeaderAccessor = packed struct {
    body_meta: bm.BodyMeta,
    context_meta: ?cm.ContextMeta,

    message_len: []const u8, //(1-2) bytes
    message_num: []const u8, // (0-3) bytes
    object: []const u8, // (0-3) bytes
    method: []const u8, // (0-1) byte
    session: []const u8, // (0-3) bytes
    process: []const u8, // (0-16) bytes
    header_len: usize,

    pub fn get_message_len(self: HeaderAccessor) u16 {
        // Используем компактную версию с прямым @bitCast для 2 байт
        if (self.message_len.len == 2) {
            return @as(u16, self.message_len[0]) << 8 | self.message_len[1];
        }
        return self.message_len[0];
    }

    pub fn get_message_num(self: HeaderAccessor) u32 {
        // Используем switch для выбора оптимальной стратегии для каждой длины
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

    pub inline fn set_method(self: *HeaderAccessor, value: ?u8) void {
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

        if (body_meta.next_meta_byte) {
            const context_meta = try cm.ContextMeta.parse(package[1]);
            scan(package, body_meta, context_meta);
        } else {
            scan(package, body_meta, null);
        }
    }

    pub fn build(package: []const u8, body_meta: bm.BodyMeta, context_meta: ?cm.ContextMeta) !HeaderAccessor {
        package[0] = body_meta.build();

        if (body_meta.next_meta_byte) {
            package[1] = context_meta.build();
            scan(package, body_meta, context_meta);
        } else {
            scan(package, body_meta, null);
        }
    }

    pub fn scan(package: []const u8, body_meta: bm.BodyMeta, context_meta: ?cm.ContextMeta) void {
        var pos = if (body_meta.next_meta_byte) 2 else 1;

        // message_len
        const message_len_size = if (body_meta.message_len_duble) 2 else 1;
        const message_len = package[pos .. pos + message_len_size];
        pos += body_meta.message_len_size;

        // message_num
        const message_num = package[pos .. pos + body_meta.message_num_len];
        pos += body_meta.message_num_len;

        // object
        const object = package[pos .. pos + body_meta.object_len];
        pos += body_meta.object_len;

        // method
        const method = package[pos .. pos + 1];
        pos += 1;

        if (context_meta != null) {

            // session
            const session = package[pos .. pos + context_meta.session_len];
            pos += context_meta.session;

            // process
            const process = package[pos .. pos + context_meta.process_len];
            pos += context_meta.process;

            return HeaderAccessor{
                .body_meta = body_meta,
                .context_meta = context_meta,
                .message_len = message_len,
                .message_num = message_num,
                .object = object,
                .method = method,
                .session = session,
                .process = process,
                .header_len = pos,
            };
        }

        return HeaderAccessor{
            .body_meta = body_meta,
            .message_len = message_len,
            .message_num = message_num,
            .object = object,
            .method = method,
            .len = pos,
        };
    }
};

// todo test
