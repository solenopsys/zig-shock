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
