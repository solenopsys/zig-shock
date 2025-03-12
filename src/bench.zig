const std = @import("std");
const parser = @import("optimized-parser.zig");

// Предотвращает оптимизацию компилятором
pub var GLOBAL_COUNTER: u64 = 0;

pub fn preventOptimization(value: anytype) void {
    _ = value;
    GLOBAL_COUNTER += 1;
    asm volatile ("" ::: "memory");
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
    const random = prng.random();

    var stdout = std.io.getStdOut().writer();
    const iterations = 100_000;

    // Создаем пул предварительно выделенных буферов для reuse
    const max_package_size = 128; // Максимальный размер пакета
    var prealloc_buffer = try allocator.alloc(u8, max_package_size * iterations);
    defer allocator.free(prealloc_buffer);

    // Подготовка случайных данных для тестов build
    try stdout.print("Подготовка случайных данных для build benchmark...\n", .{});
    var build_packages = std.ArrayList(struct {
        body: []u8,
        message_num: u32,
        object: u32,
        method: u8,
        session: u32,
        process: []u8,
    }).init(allocator);
    defer {
        for (build_packages.items) |item| {
            allocator.free(item.body);
            allocator.free(item.process);
        }
        build_packages.deinit();
    }

    for (0..iterations) |_| {
        const body_size = random.intRangeAtMost(usize, 1, 32);
        const body = try generateRandomData(allocator, &random, body_size);

        const process_len = random.intRangeAtMost(usize, 0, 3);
        const process = try generateRandomData(allocator, &random, process_len);

        try build_packages.append(.{
            .body = body,
            .message_num = random.int(u32),
            .object = random.int(u32) & 0xFFFFFF,
            .method = random.int(u8),
            .session = random.int(u32) & 0xFFFFFF,
            .process = process,
        });
    }

    // ===== ОРИГИНАЛЬНЫЙ BUILD BENCHMARK =====
    try stdout.print("Запуск original build benchmark...\n", .{});

    var original_builder = parser.SHOCKPackageBuilder.init(allocator);

    // Разогрев
    const warmup_pkg = try original_builder.build(&[_]u8{1}, 0, 0, 0, 0, &[_]u8{});
    allocator.free(warmup_pkg);

    // Сброс таймера и начало измерения
    var timer = try std.time.Timer.start();
    const original_build_start = timer.lap();

    var original_dummy_sum: usize = 0;

    for (0..iterations) |i| {
        const pkg_data = build_packages.items[i];

        const pkg = try original_builder.build(pkg_data.body, pkg_data.message_num, pkg_data.object, pkg_data.method, pkg_data.session, pkg_data.process);

        original_dummy_sum += pkg.len;
        allocator.free(pkg);
    }

    const original_build_end = timer.lap();
    const original_build_avg = @as(f64, @floatFromInt(original_build_end - original_build_start)) /
        @as(f64, @floatFromInt(iterations));

    // ===== КЭШИРУЮЩИЙ BUILD BENCHMARK =====
    try stdout.print("Запуск cached build benchmark...\n", .{});

    var cached_builder = parser.SHOCKPackageBuilder.init(allocator);
    defer cached_builder.deinit();

    // Разогрев
    _ = try cached_builder.build(&[_]u8{1}, 0, 0, 0, 0, &[_]u8{});

    const cached_build_start = timer.lap();

    var cached_dummy_sum: usize = 0;

    for (0..iterations) |i| {
        const pkg_data = build_packages.items[i];

        const pkg = try cached_builder.build(pkg_data.body, pkg_data.message_num, pkg_data.object, pkg_data.method, pkg_data.session, pkg_data.process);

        cached_dummy_sum += pkg.len;
        // Не освобождаем память, так как используем кэширование буфера
    }

    const cached_build_end = timer.lap();
    const cached_build_avg = @as(f64, @floatFromInt(cached_build_end - cached_build_start)) /
        @as(f64, @floatFromInt(iterations));

    // ===== PREALLOC BUILD BENCHMARK =====
    try stdout.print("Запуск prealloc build benchmark...\n", .{});

    var prealloc_builder = parser.SHOCKPackageBuilder.init(allocator);

    // Разогрев с использованием prealloc buffer
    _ = try prealloc_builder.build_into(prealloc_buffer[0..max_package_size], &[_]u8{1}, 0, 0, 0, 0, &[_]u8{});

    const prealloc_build_start = timer.lap();

    var prealloc_dummy_sum: usize = 0;

    for (0..iterations) |i| {
        const pkg_data = build_packages.items[i];
        const buffer_slice = prealloc_buffer[i * max_package_size .. (i + 1) * max_package_size];

        const pkg_len = try prealloc_builder.build_into(buffer_slice, pkg_data.body, pkg_data.message_num, pkg_data.object, pkg_data.method, pkg_data.session, pkg_data.process);

        prealloc_dummy_sum += pkg_len;
    }

    const prealloc_build_end = timer.lap();
    const prealloc_build_avg = @as(f64, @floatFromInt(prealloc_build_end - prealloc_build_start)) /
        @as(f64, @floatFromInt(iterations));

    // ===== PARSE BENCHMARK =====
    try stdout.print("Подготовка данных для parse benchmark...\n", .{});
    var parse_packages = std.ArrayList([]u8).init(allocator);
    defer {
        for (parse_packages.items) |pkg| {
            allocator.free(pkg);
        }
        parse_packages.deinit();
    }

    // Используем уже оптимизированный билдер для подготовки тестовых данных
    for (0..iterations) |i| {
        const pkg_data = build_packages.items[i];
        const pkg = try original_builder.build(pkg_data.body, pkg_data.message_num, pkg_data.object, pkg_data.method, pkg_data.session, pkg_data.process);
        try parse_packages.append(pkg);
    }

    try stdout.print("Запуск parse benchmark...\n", .{});

    // Разогрев
    _ = try parser.SHOCKPackageParser.parse(parse_packages.items[0]);

    const parse_start = timer.lap();

    var result_sum: usize = 0;

    for (0..iterations) |i| {
        const pkg = try parser.SHOCKPackageParser.parse(parse_packages.items[i]);
        result_sum += pkg.header_len + pkg.body.len;
    }

    const parse_end = timer.lap();
    const parse_avg = @as(f64, @floatFromInt(parse_end - parse_start)) /
        @as(f64, @floatFromInt(iterations));

    // Предотвращаем оптимизацию
    preventOptimization(original_dummy_sum);
    preventOptimization(cached_dummy_sum);
    preventOptimization(prealloc_dummy_sum);
    preventOptimization(result_sum);

    // Выводим результаты
    try stdout.print("\nРезультаты бенчмарка:\n", .{});
    try stdout.print("Original build avg: {d:.2} ns\n", .{original_build_avg});
    try stdout.print("Cached build avg:   {d:.2} ns\n", .{cached_build_avg});
    try stdout.print("Prealloc build avg: {d:.2} ns\n", .{prealloc_build_avg});
    try stdout.print("Parse avg:          {d:.2} ns\n", .{parse_avg});

    try stdout.print("\nУскорение:\n", .{});
    try stdout.print("Cached vs Original:   {d:.2}x\n", .{original_build_avg / cached_build_avg});
    try stdout.print("Prealloc vs Original: {d:.2}x\n", .{original_build_avg / prealloc_build_avg});
    try stdout.print("Prealloc vs Cached:   {d:.2}x\n", .{cached_build_avg / prealloc_build_avg});

    try stdout.print("\nVerification sums: original={d}, cached={d}, prealloc={d}, parse={d}\n", .{ original_dummy_sum, cached_dummy_sum, prealloc_dummy_sum, result_sum });
}
