pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("hardware/gpio.h");
    @cInclude("hardware/spi.h");
});
const std = @import("std");
const shell = @import("shell/shell.zig");
const SD = @import("driver/sd.zig").SD;

const PICO_DEFAULT_LED_PIN = 25;
const SD_BLOCK_SIZE = 512;
export fn main() c_int {
    // set StdioUsb to false in buils.zig
    _ = p.stdio_init_all();

    p.gpio_init(PICO_DEFAULT_LED_PIN);
    p.gpio_set_dir(PICO_DEFAULT_LED_PIN, true);

    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.sleep_ms(2000);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    _ = p.printf("Hello world\n");
    var sd = SD.init(
        @ptrCast(@as(*anyopaque, @ptrFromInt(0x4003c000))),
        22, // CS pin
        24, // SCK pin
        25, // MOSI pin
        21, // MISO pin
        1000000,
    ) catch |err| {
        _ = p.printf("SD init failed: %d\n", @intFromError(err));
        return -1;
    };
    var write_buffer: [SD_BLOCK_SIZE]u8 = undefined;
    @memset(&write_buffer, 0xAA);
    sd.writeBlock(0, &write_buffer) catch |err| {
        _ = p.printf("Write failed: %d\n", @intFromError(err));
        return -1;
    };
    @memset(&write_buffer, 0x93);
    sd.writeBlock(4, &write_buffer) catch |err| {
        _ = p.printf("Write failed: %d\n", @intFromError(err));
        return -1;
    };
    var read_buffer: [SD_BLOCK_SIZE]u8 = undefined;
    sd.readBlock(4, &read_buffer) catch |err| {
        _ = p.printf("Read failed: %d\n", @intFromError(err));
        return -1;
    };
    sd.readBlock(0, &read_buffer) catch |err| {
        _ = p.printf("Read failed: %d\n", @intFromError(err));
        return -1;
    };
    _ = p.printf("blk0 (hex):\n");
    for (read_buffer, 0..) |byte, i| {
        if (i % 16 == 0) {
            _ = p.printf("%04X: ", i);
        }
        _ = p.printf("%02X ", byte);
        if (i % 16 == 15) {
            _ = p.printf("\n");
        }
    }
    _ = p.printf("\n");
    // defer sd.deinit();
    shell.initShell();
    return 0;
}
