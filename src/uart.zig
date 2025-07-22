// const std = @import("std");
// const hw = @cImport({
//     @cInclude("pico/stdlib.h");
//     @cInclude("hardware/uart.h");
// });

// //GPIO 0 - TX
// //GPIO 1 - RX
// //GND - GND
// //Baud = how many bits per second were sent

// const BAUD_RATE: i32 = 115200;
// const UART_TX: u8 = 0;
// const UART_RX: u8 = 1;

// pub fn uartMain() void {
//     const uart = hw.uart0;
//     hw.uart_init(uart, BAUD_RATE);
//     hw.gpio_set_function(UART_TX, hw.GPIO_FUNC_UART);
//     hw.gpio_set_function(UART_RX, hw.GPIO_FUNC_UART);
//     const msg: u8 = "Hello from the upside down";
//     for (msg) |character| {
//         hw.uart_putc_raw(uart, character);
//     }

//     while (true) {
//         if (hw.uart_is_readable(uart)) {
//             const ch: u8 = hw.uart_getc(uart);
//             hw.uart_putc_raw(uart, ch);
//         }
//     }
// }
