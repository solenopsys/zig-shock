const std = @import("std");
const parser = @import("parser.zig");
const builder = @import("builder.zig");

// Глобальные переменные для предотвращения оптимизации
pub var PREVENT_OPTIMIZE_BUILD: u64 = 0;
pub var PREVENT_OPTIMIZE_PARSE: u64 = 0;

// Функция, которая гарантированно предотвращает оптимизацию
// Использует волатильный asm
pub fn preventOptimization(value: anytype) @TypeOf(value) {
    asm volatile (""
        :
        : [val] "r" (value),
        : "memory"
    );
    return value;
}

// Генерирует случайные данные для тестов
fn generateRandomData(allocator: std.mem.Allocator, prng: *std.Random, size: usize) ![]u8 {
    const data = try allocator.alloc(u8, size);
    for (data) |*byte| {
        byte.* = prng.intRangeAtMost(u8, 0, 255);
    }
    return data;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Инициализируем генератор случайных чисел
    var prng = std.Random.DefaultPrng.init(@as(u64, @bitCast(std.time.timestamp())));
    var random = prng.random();

    var stdout = std.io.getStdOut().writer();

    // Количество итераций
    const iterations = 10_000;

    // Создаем пул предварительно выделенных буферов
    const max_package_size = 128;
    var prealloc_buffer = try allocator.alloc(u8, max_package_size * iterations);
    defer allocator.free(prealloc_buffer);

    // Подготовка тестовых данных
    try stdout.print("Подготовка тестовых данных...\n", .{});
    var test_packages = std.ArrayList(struct {
        body: []u8,
        message_num: u32,
        object: u32,
        method: u8,
        session: u32,
        process: []u8,
    }).init(allocator);
    defer {
        for (test_packages.items) |item| {
            allocator.free(item.body);
            allocator.free(item.process);
        }
        test_packages.deinit();
    }

    for (0..iterations) |_| {
        const body_size = random.intRangeAtMost(usize, 1, 32);
        const body = try generateRandomData(allocator, &random, body_size);

        const process_len = random.intRangeAtMost(usize, 0, 3);
        const process = try generateRandomData(allocator, &random, process_len);

        try test_packages.append(.{
            .body = body,
            .message_num = random.int(u32),
            .object = random.int(u32) & 0xFFFFFF,
            .method = random.int(u8),
            .session = random.int(u32) & 0xFFFFFF,
            .process = process,
        });
    }

    // Инициализация билдера
    var shock_builder = builder.SHOCKPackageBuilder.init(allocator);

    // Массив для хранения размеров пакетов
    var pkg_sizes = try allocator.alloc(usize, iterations);
    defer allocator.free(pkg_sizes);

    // ==== Тестирование build_into ====
    try stdout.print("Запуск build_into benchmark...\n", .{});

    // Разогрев с гарантированным использованием результата
    const warmup_size = try shock_builder.build_into(prealloc_buffer[0..max_package_size], &[_]u8{1}, 0, 0, 0, 0, &[_]u8{});
    _ = preventOptimization(warmup_size);

    // Запуск таймера
    var timer = try std.time.Timer.start();
    const build_start = timer.read();

    for (0..iterations) |i| {
        const pkg_data = test_packages.items[i];
        const buffer_slice = prealloc_buffer[i * max_package_size .. (i + 1) * max_package_size];

        pkg_sizes[i] = try shock_builder.build_into(buffer_slice, pkg_data.body, pkg_data.message_num, pkg_data.object, pkg_data.method, pkg_data.session, pkg_data.process);

        // Накапливаем результат и делаем его volatile
        PREVENT_OPTIMIZE_BUILD +%= preventOptimization(pkg_sizes[i]);
    }

    const build_end = timer.read();
    const build_time_ns = @as(f64, @floatFromInt(build_end - build_start));
    const build_avg = build_time_ns / @as(f64, @floatFromInt(iterations));

    // ==== Подготовка для тестирования парсера ====
    try stdout.print("Подготовка данных для parse benchmark...\n", .{});

    // Используем тот же буфер для парсинга
    // Пакеты уже построены в предыдущем шаге

    // ==== Тестирование парсера ====
    try stdout.print("Запуск parse benchmark...\n", .{});

    var shock_parser = parser.SHOCKPackageParser.init();

    // Разогрев парсера с гарантированным использованием результата
    const warmup_pkg = try shock_parser.parse(prealloc_buffer[0..pkg_sizes[0]]);
    PREVENT_OPTIMIZE_PARSE +%= preventOptimization(warmup_pkg.header_len);
    PREVENT_OPTIMIZE_PARSE +%= preventOptimization(warmup_pkg.body.len);

    const parse_start = timer.read();

    // Проводим измерение с гарантированным использованием результатов
    for (0..iterations) |i| {
        const actual_size = pkg_sizes[i];
        const buffer_slice = prealloc_buffer[i * max_package_size .. i * max_package_size + actual_size];

        const parsed_pkg = try shock_parser.parse(buffer_slice);

        // Гарантированно используем результаты
        PREVENT_OPTIMIZE_PARSE +%= preventOptimization(parsed_pkg.header_len);
        PREVENT_OPTIMIZE_PARSE +%= preventOptimization(parsed_pkg.body.len);

        // Дополнительно используем другие поля результата
        if (parsed_pkg.body_meta.message_num_len > 0) {
            PREVENT_OPTIMIZE_PARSE +%= 1;
        }
        if (parsed_pkg.context_meta != null) {
            PREVENT_OPTIMIZE_PARSE +%= 1;
        }
    }

    const parse_end = timer.read();
    const parse_time_ns = @as(f64, @floatFromInt(parse_end - parse_start));
    const parse_avg = parse_time_ns / @as(f64, @floatFromInt(iterations));

    // Выводим результаты
    try stdout.print("\nРезультаты бенчмарка:\n", .{});
    try stdout.print("Build avg: {d:.2} ns\n", .{build_avg});
    try stdout.print("Parse avg: {d:.2} ns\n", .{parse_avg});
    try stdout.print("Build/Parse ratio: {d:.2}x\n", .{build_avg / parse_avg});

    // Выводим контрольные суммы
    try stdout.print("\nКонтрольные суммы (для проверки):\n", .{});
    try stdout.print("Build checksum: {d}\n", .{PREVENT_OPTIMIZE_BUILD});
    try stdout.print("Parse checksum: {d}\n", .{PREVENT_OPTIMIZE_PARSE});
}
