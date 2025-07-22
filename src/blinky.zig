const std = @import("std");
const gpio = @cImport({
    @cInclude("pico/stdlib.h");
});
// const bi = @cImport({@CInclude("pico/binary_info.h");});
pub fn main() void {
    // bi.bi_decl(bi_program_description("First blink huhaha"));
    //Doesn't work in zig cuz its not a fxn, its a macro it seems

    gpio.stdio_init_all();
    const LED_PIN: u16 = 25;
    gpio.gpio_init(LED_PIN);
    gpio.gpio_set_dir(LED_PIN, gpio.GPIO_OUT);
    while (1) {
        gpio.gpio_put(LED_PIN, 0);
        gpio.sleep_ms(2500);
        gpio.gpio_put(LED_PIN, 1);
        gpio.sleep_ms(2500);
    }
}
