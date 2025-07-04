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

// const generic_func  = *fn(*anyopaque) ?*anyopaque;
const generic_func  = *const fn(ctx: *anyopaque) void;

// assembly method definitions
extern fn foo(a: u32, b: u32) u32; // DEBUG
extern fn isr_svcall() void;
extern fn __piccolo_task_init_stack(n: *u32) void;
extern fn __piccolo_pre_switch(n: *u32) void;
extern fn piccolo_yield() void;

const Task = struct {
    callback: generic_func,
    data: ?*anyopaque,

    fn new(task_func: generic_func, data: *anyopaque) Task {
        return Task {
            .callback = task_func,
            .data = data,
        };
    }
};

const TOTAL_TASKS: usize = 10;

const Sched = struct {
    stacks: [10][256]u32,
    tasks: [10]*u32,

    task_count: usize,
    current_task: usize,

    const Self = @This();

    pub fn new() Self {
        const ret = Sched {
            .stacks = .{.{0} ** 256} ** 10,
            .tasks = undefined,
            .task_count = 0,
            .current_task = 0,
        };

        return ret;
    }

    pub fn create_task(self: *Self, task: Task, n: usize) void {

        // we mimick the stack frame
        // 256 - 17 -> how much we are pushing to the stack
        const offset: usize = 239;
        self.stacks[n][offset + 8] = 0xFFFFFFFD;
        self.stacks[n][offset + 15] = @as(u32, @intFromPtr(task.callback));
        self.stacks[n][offset + 16] = 0x01000000;
        
        self.tasks[n] = &self.stacks[n][offset];

        self.task_count += 1;
    }

    pub fn next(self: *Self) *u32 {
        self.current_task = @mod(self.current_task + 1, self.task_count);
        return self.tasks[self.current_task];
    }
};

var sched = Sched.new();

fn sched_callback(alarm_num: c_uint) callconv(.c) void {
    isr_svcall();

    _ = p.printf("[DEBUG] sched_callback running %d\n", alarm_num);
    // const timer = p.hardware_get_num
    // const alarm_id = timer[0].alarm_id;
    // const time  = p.time_us_64();
    // _ = p.printf("[DEBUG][TIMER %d] walker callback at %lld\r\n", alarm_id, time);

    // var sched = @as(*Sched, @ptrCast(@alignCast(user_data)));
    const task_ptr = sched.next();
    
    const timeout = p.make_timeout_time_ms(2000);
    _ = p.hardware_alarm_set_target(0, timeout);
    __piccolo_pre_switch(task_ptr);

    // return true;
    // _ = p.printf("[DEBUG] timer couldnt find user data");
    // return true;
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

// custom function
const foo_data = struct {};
fn foo_task(ctx: *anyopaque) void {
    _ = ctx;
    while (true) {
        _ = p.printf("[FOO TASK]: hello!\r\n");
        p.gpio_put(25, true);
        p.sleep_ms(200);
        p.gpio_put(25, false);
        p.sleep_ms(200);
    }
}

const bar_data = struct {};
fn bar_task(ctx: *anyopaque) void {
    _ = ctx;
    while (true) {
        _ = p.printf("[BAR TASK]: hello!\r\n");
        p.sleep_ms(500);
    }
}

export fn main() c_int {
    _ = p.stdio_init_all();

    p.gpio_init(25);
    p.gpio_set_dir(25, true);
    p.sleep_ms(2000);

    for (0..10) |_| {
        p.gpio_put(25, true);
        p.sleep_ms(100);
        p.gpio_put(25, false);
        p.sleep_ms(100);
    }

    var foo_task_data = foo_data{};
    var bar_task_data = bar_data{};

    const task_foo = Task.new(foo_task, &foo_task_data);
    const task_bar = Task.new(bar_task, &bar_task_data);

    sched.create_task(task_foo, 0);
    sched.create_task(task_bar, 1);

    p.hardware_alarm_set_callback(0, sched_callback);
    const timeout = p.make_timeout_time_ms(2000);
    _ = p.hardware_alarm_set_target(0, timeout);

    __piccolo_pre_switch(sched.next());

    while(true) {
    }

    return 0;
}
