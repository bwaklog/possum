pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    // PICO W specific header
    @cInclude("hardware/timer.h");
    @cInclude("hardware/watchdog.h");
    @cInclude("setjmp.h");
    @cInclude("pico/time.h");
});
const std = @import("std");

const task = @import("executor/task.zig");
const executor = @import("executor/executor.zig");

fn walker_callback(timer: [*c]p.repeating_timer_t) callconv(.c) bool {
    const alarm_id = timer[0].alarm_id;

    const time  = p.time_us_64();

    _ = p.printf("[DEBUG][TIMER %d] walker callback at %lld\r\n", alarm_id, time);

    return true;
}

export fn main() c_int {
    _ = p.stdio_init_all();

    p.gpio_init(25);
    p.gpio_set_dir(25, true);
    p.sleep_ms(2000);

    for (0..5) |_| {
        p.gpio_put(25, true);
        p.sleep_ms(100);
        p.gpio_put(25, false);
        p.sleep_ms(100);
    }



    var timer: p.repeating_timer_t = undefined;
    const rep_timer = @as([*c]p.repeating_timer_t, &timer);
    
    _ = p.add_repeating_timer_ms(
        2000, 
        walker_callback, 
        p.NULL, 
        rep_timer
    );

    while (true) {
        _ = p.printf("main loop\r\n");
        for (0..10) |_| {
            p.gpio_put(25, true);
            p.sleep_ms(50);
            p.gpio_put(25, false);
            p.sleep_ms(50);
        }
    }

    return 0;
}
