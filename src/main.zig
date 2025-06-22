pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("hardware/gpio.h");
});
const std = @import("std");
const shell = @import("shell/shell.zig");

const PICO_DEFAULT_LED_PIN = 25;

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

    p.sleep_ms(2000);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    _ = p.printf("Hello world\n");
    shell.initShell();
    return 0;
}
