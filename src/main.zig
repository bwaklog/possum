const p = @import("common/common.zig").p;
const common = @import("common/common.zig");
const addr = @import("common/addrs.zig");
const task = @import("task/task.zig");
const shceduler = @import("scheduler/scheduler.zig");
const timer = @import("timer/timer.zig");

const init = @import("init.zig");

var sched = shceduler.Scheduler.new();

// custom function
const foo_data = struct {};
fn foo_task(ctx: *anyopaque) void {
    var i: c_uint = 0;
    _ = ctx;

    while (true) {
        _ = p.printf("[FOO TASK]: hello %d!\r\n", i);
        p.sleep_ms(200);

        i += 1;
    }
}

const bar_data = struct {};
fn bar_task(ctx: *anyopaque) void {
    var j: c_uint = 0;
    _ = ctx;
    while (true) {
        _ = p.printf("[BAR TASK]: hello %d\r\n", j);
        // check_control();

        j += 1;
        p.sleep_ms(200);
        // busy_wait(500_000);
    }
}

fn baz_task(ctx: *anyopaque) void {
    _ = ctx;
    while (true) {
        _ = p.printf("[BAZ TASK]\r\n");
        // check_control();
        p.gpio_put(25, true);
        p.sleep_ms(250);
        p.gpio_put(25, false);
        p.sleep_ms(250);
    }
}

export fn main() c_int {

    init.init();

    sched.create_task(foo_task, null, 0);
    sched.create_task(bar_task, null, 0);
    sched.create_task(baz_task, null, 0);

    _ = p.printf("initialised tasks\r\n");

    var dummy_stack = [_]c_uint{0} ** 32;
    common.task_init_stack(&dummy_stack[0]);

    sched.current_task = 0;

    while (true) {

        _ = p.printf("start of loop\r\n");

        timer.systick_config(common.TIME_SLICE);

        sched.tasks[sched.current_task].stack_start = common.pre_switch(sched.tasks[sched.current_task].stack_start);
        sched.next();

        p.sleep_ms(500);

        _ = p.printf("[DEBUG] Switch back to MSP, outside of task\r\n");
    }

    return 0;
}
