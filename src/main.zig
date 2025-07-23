const std = @import("std");
const p = @import("common/common.zig").p;
const common = @import("common/common.zig");
const addr = @import("common/addrs.zig");
const task = @import("task/task.zig");
const shceduler = @import("scheduler/scheduler.zig");
const timer = @import("timer/timer.zig");
const uart = @import("uart/uart.zig");

const init = @import("init.zig");

var sched = shceduler.Scheduler.new();

fn interface_core1() callconv(.C) void {
    _ = p.stdio_init_all();

    while (true) {
        const prog_data_opt = task.receive_program_uart();
        if (prog_data_opt) |prog_data| {
            const prog_ptr: *const fn (*anyopaque) void = @as(*const fn (*anyopaque) void, @ptrFromInt(@intFromPtr(&prog_data.data[0]) + prog_data.entry_offset));
            sched.lock();
            sched.create_task(prog_ptr, null, 0);
            sched.unlock();
        } else {
            _ = p.printf("[CORE 1] Failed to load program over UART\r\n");
        }
    }
}

fn foo_task(ctx: *anyopaque) void {
    var i: u32 = 0;
    _ = ctx;
    while (true) {
        _ = p.printf("[FOO TASK]: hello %d!\r\n", i);
        p.sleep_ms(200);
        i += 1;
    }
}

fn bar_task(ctx: *anyopaque) void {
    var j: u32 = 0;
    _ = ctx;
    while (true) {
        _ = p.printf("[BAR TASK]: hello %d\r\n", j);
        j += 1;
        p.sleep_ms(200);
    }
}

fn baz_task(ctx: *anyopaque) void {
    _ = ctx;
    while (true) {
        _ = p.printf("[BAZ TASK]\r\n");
        p.gpio_put(25, true);
        p.sleep_ms(250);
        p.gpio_put(25, false);
        p.sleep_ms(250);
    }
}

fn new_task(ctx: *anyopaque) void {
    _ = ctx;
    for (0..1000000000) |i| {
        _ = p.printf("WOWWW NEW FN numbner:\r\n");
        _ = p.printf(i);
        p.sleep_ms(50);
    }
}

export fn main() c_int {
    init.init();

    _ = p.printf("BEFORE LAUNCH");
    p.multicore_launch_core1(interface_core1);
    _ = p.printf("AFTER LAUNCH");

    sched.lock();
    sched.create_task(foo_task, null, 0);
    // sched.create_task(bar_task, null, 0);
    // sched.create_task(baz_task, null, 0);
    sched.unlock();

    p.sleep_ms(500);
    _ = p.printf("initialised tasks\r\n");

    var dummy_stack = [_]u32{0} ** 32;
    common.task_init_stack(&dummy_stack[0]);

    sched.current_task = 0;

    while (true) {
        sched.lock();
        timer.systick_config(common.TIME_SLICE);
        const stack_start = sched.tasks[sched.current_task].stack_start;
        sched.unlock();

        const return_psp = common.pre_switch(stack_start);

        sched.lock();
        sched.tasks[sched.current_task].stack_start = return_psp;
        sched.next();
        sched.unlock();

        _ = p.printf("[DEBUG] Switch back to MSP, outside of task\r\n");
    }
    return 0;
}
