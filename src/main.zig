pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    // PICO W specific header
    @cInclude("hardware/timer.h");
    @cInclude("hardware/watchdog.h");
    @cInclude("setjmp.h");
    @cInclude("pico/time.h");

    @cInclude("hardware/structs/systick.h");
    @cInclude("hardware/sync.h");
});



const std = @import("std");

fn walker_callback(timer: [*c]p.repeating_timer_t) callconv(.c) bool {
    const alarm_id = timer[0].alarm_id;

    const time  = p.time_us_64();

    _ = p.printf("[DEBUG][TIMER %d] walker callback at %lld\r\n", alarm_id, time);

    return true;
}

fn systick_config(n: c_ulong) void {
    (p.systick_hw.*).csr = 0;
    p.__dsb();
    p.__isb();

    var icsr_base = (p.PPB_BASE + p.M0PLUS_ICSR_OFFSET);
    var icsr_base_cast: [*c]volatile p.io_rw_32 = @volatileCast(@as([*c]p.io_rw_32, &icsr_base));
    p.hw_set_bits((&icsr_base_cast).*, p.M0PLUS_ICSR_BITS);

    (p.systick_hw.*).rvr = n - 1;
    (p.systick_hw.*).cvr = 0;
    (p.systick_hw.*).csr = 0x03;
}

fn init_stack(stack: *c_uint) void {
    asm volatile(
        \\ mrs ip, xpsr
        \\ push {r4, r5, r6, r7, lr}
        \\ mov r1, r8
        \\ mov r2, r9
        \\ mov r3, r10
        \\ mov r4, r11
        \\ mov r5, r12
        \\ push {r1, r2, r3, r4, r5}    
        \\
        \\ msr psp, r0
        \\ movs r0, #2
        \\ msr control, r0
        \\ isb
    );
    _ = stack;
}

export fn main() c_int {
    _ = p.stdio_init_all();

    var dummy_stack: [32]c_uint = [_]c_uint{0} ** 32;

    // var ptr_opr = @as(*c_uint, @ptrFromInt(@intFromPtr(dummy_stack))) + @as(*c_uint, @ptrFromInt(32));
    init_stack(@as(*c_uint, @ptrFromInt(@intFromPtr(&dummy_stack[0]) + 32)));

    var shrp2_base = (p.PPB_BASE + p.M0PLUS_SHPR2_OFFSET);
    var shrp2_base_cast: [*c]volatile p.io_rw_32 = @volatileCast(@as([*c]p.io_rw_32, &shrp2_base));
    p.hw_set_bits((&shrp2_base_cast).*, p.M0PLUS_SHPR2_BITS);

    var shrp3_base = (p.PPB_BASE + p.M0PLUS_SHPR3_OFFSET);
    var shrp3_base_cast: [*c]volatile p.io_rw_32 = @volatileCast(@as([*c]p.io_rw_32, &shrp3_base));
    p.hw_set_bits((&shrp3_base_cast).*, p.M0PLUS_SHPR3_BITS);

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
