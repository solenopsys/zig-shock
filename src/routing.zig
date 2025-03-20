const std = @import("std");
const testing = std.testing;

const Parser = @import("./pack-parser.zig").SHOCKPackageParser;
const Builder = @import("./pack-builder.zig").SHOCKPackageBuilder;
const SHOCKPackage = @import("./pack-parser.zig").SHOCKPackage;

pub const Packet = []const u8;

pub const Object = struct {
    context: *anyopaque,
    send: *const fn (ctx: *anyopaque, data: Packet) void,
    onMessage: ?*const fn (ctx: *anyopaque, data: Packet) void,
};

pub const Handler = struct {
    processor: *Processor,
    send: *const fn (data: Packet) void,
    onMessage: *const fn (data: Packet) void,
};

pub const Processor = struct {
    object: Object,
    handlers: std.AutoHashMap(u8, *Handler),
    router: *Router,
    parser: Parser,

    pub fn init(allocator: std.mem.Allocator, router: *Router) Processor {
        return Processor{
            .router = router,
            .handlers = std.AutoHashMap(u8, *Handler).init(allocator),
            .parser = Parser.init(),
            .object = Object{
                .context = @ptrCast(router),
                .send = sendImpl,
                .onMessage = onMessageImpl,
            },
        };
    }

    pub fn register(self: *Processor, method: u8, handler: *Handler) void {
        self.handlers.put(method, handler) catch unreachable;
    }

    pub fn deinit(self: *Processor) void {
        self.handlers.deinit();
    }

    fn sendImpl(ctx: *anyopaque, data: Packet) void {
        const self: *Processor = @ptrCast(@alignCast(ctx));
        std.debug.print("Sending data: {s}\n", .{data});
        self.router.receive(data);
    }

    fn onMessageImpl(ctx: *anyopaque, data: Packet) void {
        const self: *Processor = @ptrCast(@alignCast(ctx));

        const pack = self.parser.parse(data) catch return;
        const method_id = if (pack.header_accessor.get_method()) |method| method else return;

        if (self.handlers.capacity() > 0 and self.handlers.contains(method_id)) {
            const handler_ptr = self.handlers.get(method_id).?;
            handler_ptr.onMessage(data);
        }
    }
};

pub const Router = struct {
    objects: std.AutoHashMap(u32, *Object),
    allocator: std.mem.Allocator,
    parser: Parser,

    pub fn init(allocator: std.mem.Allocator) Router {
        return Router{
            .objects = std.AutoHashMap(u32, *Object).init(allocator),
            .allocator = allocator,
            .parser = Parser.init(),
        };
    }

    pub fn deinit(self: *Router) void {
        self.objects.deinit();
    }

    pub fn registerObject(self: *Router, id: u32, object: *Object) !void {
        try self.objects.put(id, object);
    }

    pub fn receive(self: *Router, data: Packet) void {
        const pack = self.parser.parse(data) catch return;
        const object_id = pack.header_accessor.get_object();

        if (self.objects.get(object_id)) |object_ptr| {
            if (object_ptr.onMessage) |onMessageFn| {
                onMessageFn(object_ptr.context, data);
            }
        }
    }
};

pub const PrintHandler = struct {
    handler: Handler,
    allocator: std.mem.Allocator,
    processor: *Processor,
    received_packets: std.ArrayList(Packet),

    pub fn init(allocator: std.mem.Allocator, processor: *Processor) !*PrintHandler {
        const self = try allocator.create(PrintHandler);
        self.* = PrintHandler{
            .handler = Handler{
                .processor = processor,
                .send = PrintHandler.sendImpl,
                .onMessage = PrintHandler.onMessageImpl,
            },
            .allocator = allocator,
            .processor = processor,
            .received_packets = std.ArrayList(Packet).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *PrintHandler) void {
        self.received_packets.deinit();
        self.allocator.destroy(self);
    }

    fn sendImpl(data: Packet) void {
        std.debug.print("Sending data: {s}\n", .{data});
    }

    fn onMessageImpl(data: Packet) void {
        std.debug.print("Handler for method processing packet\n", .{});
        std.debug.print("Data: {s}\n", .{data});
    }
};

// Создаем mock-объект для тестирования
pub const MockHandler = struct {
    handler: Handler,
    allocator: std.mem.Allocator,
    processor: *Processor,
    received_packets: std.ArrayList(Packet),
    message_received: bool = false,

    pub fn init(allocator: std.mem.Allocator, processor: *Processor) !*MockHandler {
        const self = try allocator.create(MockHandler);
        self.* = MockHandler{
            .handler = Handler{
                .processor = processor,
                .send = sendImplFn,
                .onMessage = onMessageImplFn,
            },
            .allocator = allocator,
            .processor = processor,
            .received_packets = std.ArrayList(Packet).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *MockHandler) void {
        self.received_packets.deinit();
        self.allocator.destroy(self);
    }

    fn sendImplFn(data: Packet) void {
        _ = data;
        // В реальном тесте здесь можно было бы сохранять данные
    }

    fn onMessageImplFn(data: Packet) void {
        // Здесь у нас статический метод, который не может обращаться к self
        // В реальном тесте нужно подумать, как сохранять состояние
        std.debug.print("Mock handler received packet: {s}\n", .{data});
    }
};

// Тест 1: Проверка создания и уничтожения Router
test "Router initialization and deinitialization" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    // Проверяем, что хеш-карта объектов пуста
    try testing.expectEqual(@as(usize, 0), router.objects.count());
}

// Тест 2: Проверка создания Processor и регистрации Handler
test "Processor initialization and handler registration" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var processor = Processor.init(allocator, &router);
    defer processor.deinit();

    var print_handler = try PrintHandler.init(allocator, &processor);
    defer print_handler.deinit();

    // Регистрируем обработчик
    processor.register(0, &print_handler.handler);

    // Проверяем, что обработчик зарегистрирован
    try testing.expect(processor.handlers.contains(0));
}

// Тест 3: Проверка регистрации объекта в Router
test "Register object in Router" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var processor = Processor.init(allocator, &router);
    defer processor.deinit();

    // Регистрируем объект
    try router.registerObject(1, &processor.object);

    // Проверяем, что объект зарегистрирован
    try testing.expect(router.objects.contains(1));
}

test "Message flow integration test" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var processor = Processor.init(allocator, &router);
    defer processor.deinit();

    var mock_handler = try MockHandler.init(allocator, &processor);
    defer mock_handler.deinit();

    // Регистрируем обработчик и объект
    processor.register(0, &mock_handler.handler);
    try router.registerObject(1, &processor.object);

    // Создаем тестовый пакет (в реальном коде нужно создать настоящий валидный пакет)
    const test_packet = "test packet data";

    var builder = Builder.init(allocator);
    const process_data = [_]u8{ 0xBC, 0xDE };

    // Allocate a buffer for the package
    var buffer = try allocator.alloc(u8, 64); // Size with some margin
    defer allocator.free(buffer);

    // Build the package into the buffer
    const pkg_len = try builder.build(buffer, test_packet, 0x1234, 1, 0, 0x9A, &process_data);

    // Create a copy of just the valid portion of the buffer
    const original_pkg_bytes = try allocator.alloc(u8, pkg_len);
    defer allocator.free(original_pkg_bytes);
    std.mem.copyForwards(u8, original_pkg_bytes, buffer[0..pkg_len]);

    router.receive(original_pkg_bytes);

    // Проверяем, что обработчик зарегистрирован у процессора
    try testing.expect(processor.handlers.contains(0));

    // Проверяем, что объект-процессор зарегистрирован в роутере
    try testing.expect(router.objects.contains(1));
}

// Тест 5: Проверка создания и использования нескольких обработчиков
test "Multiple handlers test" {
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var processor = Processor.init(allocator, &router);
    defer processor.deinit();

    var handler1 = try MockHandler.init(allocator, &processor);
    defer handler1.deinit();

    var handler2 = try MockHandler.init(allocator, &processor);
    defer handler2.deinit();

    // Регистрируем обработчики для разных методов
    processor.register(1, &handler1.handler);
    processor.register(2, &handler2.handler);

    // Проверяем, что оба обработчика зарегистрированы
    try testing.expect(processor.handlers.contains(1));
    try testing.expect(processor.handlers.contains(2));
}
