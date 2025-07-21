const p = @import("common/common.zig").p;
const common = @import("common/common.zig");
const addr = @import("common/addrs.zig");
const task = @import("task/task.zig");
const scheduler = @import("scheduler/scheduler.zig");
const timer = @import("timer/timer.zig");

const init = @import("init.zig");

var systick = timer.SysTick.new(common.TIME_SLICE);
var sched_core0 = scheduler.Scheduler.new(scheduler.Config{
    .core = scheduler.CoreID.Core0,
    .switch_quantums = 2,
});
var sched_core1 = scheduler.Scheduler.new(scheduler.Config{
    .core = scheduler.CoreID.Core1,
    .switch_quantums = 5,
});

// custom function
fn core0_foo_task(ctx: *anyopaque) void {
    var i: c_uint = 0;
    _ = ctx;

    while (true) {
        // _ = p.printf("[CORE 0][FOO TASK]: hello %d!\r\n", i);
        p.sleep_ms(200);

        i += 1;
    }
}

fn core0_bar_task(ctx: *anyopaque) void {
    var j: c_uint = 0;
    _ = ctx;
    while (true) {
        // _ = p.printf("[CORE 0][BAR TASK]: hello %d\r\n", j);
        // check_control();

        j += 1;
        p.sleep_ms(200);
        // busy_wait(500_000);
    }
}

fn core1_baz_task(ctx: *anyopaque) void {
    _ = ctx;
    while (true) {
        // _ = p.printf("[CORE 1][BAZ TASK]\r\n");
        // check_control();
        // p.gpio_put(25, true);
        // p.sleep_ms(250);
        // p.gpio_put(25, false);
        p.sleep_ms(250);
    }
}

fn core1_qux_task(ctx: *anyopaque) void {
    _ = ctx;
    while (true) {
        // _ = p.printf("[CORE 1][QUX TASK]\r\n");
        // check_control();
        p.gpio_put(25, true);
        p.sleep_ms(250);
        p.gpio_put(25, false);
        p.sleep_ms(250);
    }
}

fn core1_entry() callconv(.c) void {

    // tasks
    sched_core1.create_task(core1_baz_task, null, 0);
    sched_core1.create_task(core1_qux_task, null, 0);
    
    // init the dummy stack
    var dummy_stack = [_]c_uint{0} ** 32;
    common.task_init_stack(&dummy_stack[0]);

    sched_core1.current_task = 0;

    _ = p.printf("[CORE 1] finished initilising tasks on the core\r\n");

    while (true) {
        // _ = p.printf("[CORE 1] Last log in Handler Mode before entering task\r\n");
        systick.disable();
        systick.set_with_config();

        sched_core1.tasks[sched_core1.current_task].stack_start = common.pre_switch(sched_core1.tasks[sched_core1.current_task].stack_start);
        // _ = p.printf("[CORE 1][DEBUG] Back in Handler Mode\r\n");
        sched_core1.next();
    }
}


export fn main() c_int {

    init.init();

    // while (true) {
    //     _ = p.printf("[CORE 0][DEBUG] please work\r\n");
    //     // check_control();
    //     p.gpio_put(25, true);
    //     p.sleep_ms(250);
    //     p.gpio_put(25, false);
    //     p.sleep_ms(250);
    // }
    
    p.multicore_launch_core1(core1_entry);

    sched_core0.create_task(core0_foo_task, null, 0);
    sched_core0.create_task(core0_bar_task, null, 0);

    _ = p.printf("[CORE 0] finished initilising tasks on the core\r\n");

    var dummy_stack = [_]c_uint{0} ** 32;
    common.task_init_stack(&dummy_stack[0]);

    sched_core0.current_task = 0;

    while (true) {

        // _ = p.printf("[CORE 0] Last log in Handler Mode before entering task\r\n");

        systick.disable();
        systick.set_with_config();

        sched_core0.tasks[sched_core0.current_task].stack_start = common.pre_switch(sched_core0.tasks[sched_core0.current_task].stack_start);
        // _ = p.printf("[CORE 0][DEBUG] Back in Handler Mode\r\n");
        sched_core0.next();

    }

    return 0;
}
