const std = @import("std");
const c = @cImport({
    @cInclude("pico/stdlib.h");
    @cInclude("stdio.h");
    @cInclude("hardware/structs/systick.h");
    @cInclude("hardware/sync.h");
    @cInclude("hardware/regs/m0plus.h");
    @cInclude("stdlib.h");
});

extern fn __piccolo_task_init_stack(stack: *u32) void;
extern fn __piccolo_pre_switch(stack: *u32) *u32;
extern fn piccolo_yield() void;

export fn __dsb() void {
    asm volatile ("dsb");
}

export fn __isb() void {
    asm volatile ("isb");
}

const PICCOLO_OS_STACK_SIZE: usize = 256;
const PICCOLO_OS_TASK_LIMIT: usize = 3;
const PICCOLO_OS_THREAD_PSP: u32 = 0xFFFFFFFD;
const PICCOLO_OS_TIME_SLICE: u32 = 10000000;

const piccolo_os_internals_t = struct {
    task_stacks: [PICCOLO_OS_TASK_LIMIT][PICCOLO_OS_STACK_SIZE]u32,
    the_tasks: [PICCOLO_OS_TASK_LIMIT]?*u32,
    task_count: usize,
    current_task: usize,
    started: bool,
};

const piccolo_sleep_t = u32;

const task_function_t = *const fn (ptr: ?*anyopaque) void;

const task_wrapper_t = struct {
    function: task_function_t,
    parameter: ?*anyopaque,
};

var piccolo_ctx: piccolo_os_internals_t = .{
    .task_stacks = std.mem.zeroes([PICCOLO_OS_TASK_LIMIT][PICCOLO_OS_STACK_SIZE]u32),
    .the_tasks = [_]?*u32{null} ** PICCOLO_OS_TASK_LIMIT,
    .task_count = 0,
    .current_task = 0,
    .started = false,
};

export var preemption_count: u32 = 0;
export var debug_sp: u32 = 0;
export var debug_lr: u32 = 0;
export var preemption_occurred: bool = false;

fn piccolo_os_create_task(task_stack: [*]u32, pointer_to_task_function: *const fn () void) *u32 {
    const stack_top = task_stack + PICCOLO_OS_STACK_SIZE - 17;

    const bytes_to_clear = 17 * @sizeOf(u32);
    const stack_bytes = @as([*]u8, @ptrCast(stack_top))[0..bytes_to_clear];
    @memset(stack_bytes, 0);

    stack_top[8] = PICCOLO_OS_THREAD_PSP;
    stack_top[15] = @intFromPtr(pointer_to_task_function);
    stack_top[16] = 0x01000000;

    return @ptrCast(stack_top);
}

fn __piccolo_task_init() void {
    var dummy: [32]u32 = undefined;
    __piccolo_task_init_stack(&dummy[0]);
}

fn piccolo_init() void {
    piccolo_ctx.task_count = 0;
    _ = c.stdio_init_all();
    c.hw_set_bits(@as([*c]c.io_rw_32, @ptrFromInt(c.PPB_BASE + c.M0PLUS_SHPR2_OFFSET)), c.M0PLUS_SHPR2_BITS);
    c.hw_set_bits(@as([*c]c.io_rw_32, @ptrFromInt(c.PPB_BASE + c.M0PLUS_ICSR_OFFSET)), c.M0PLUS_ICSR_PENDSTCLR_BITS);
    c.hw_set_bits(@as([*c]c.io_rw_32, @ptrFromInt(c.PPB_BASE + c.M0PLUS_SHPR3_OFFSET)), c.M0PLUS_SHPR3_BITS);
}

fn __piccolo_systick_config(n: u32) void {
    if (preemption_occurred) {
        _ = c.printf("PREEMPT #%lu - SP: 0x%08lx, LR: 0x%08lx, Task: %zu\n", preemption_count, debug_sp, debug_lr, piccolo_ctx.current_task);
        preemption_occurred = false;
    }

    c.systick_hw.*.csr = 0;
    __dsb();
    __isb();

    c.hw_set_bits(@as([*c]c.io_rw_32, @ptrFromInt(c.PPB_BASE + c.M0PLUS_ICSR_OFFSET)), c.M0PLUS_ICSR_PENDSTCLR_BITS);

    c.systick_hw.*.rvr = (n) - 1;
    c.systick_hw.*.cvr = 0;
    c.systick_hw.*.csr = 0x03;
}

fn piccolo_start() void {
    piccolo_ctx.current_task = 0;
    piccolo_ctx.started = true;

    __piccolo_task_init();

    _ = c.printf("Starting first task: %zu\n", piccolo_ctx.current_task);

    while (true) {
        __piccolo_systick_config(PICCOLO_OS_TIME_SLICE);
        piccolo_ctx.the_tasks[piccolo_ctx.current_task] =
            __piccolo_pre_switch(piccolo_ctx.the_tasks[piccolo_ctx.current_task].?);

        piccolo_ctx.current_task += 1;
        if (piccolo_ctx.current_task >= piccolo_ctx.task_count) {
            piccolo_ctx.current_task = 0;
        }
    }
}

var task_wrappers: [PICCOLO_OS_TASK_LIMIT]task_wrapper_t = undefined;

fn task_wrapper_func() void {
    _ = c.printf("Task wrapper executing for task %zu\n", piccolo_ctx.current_task);
    const wrapper = &task_wrappers[piccolo_ctx.current_task];
    wrapper.function(wrapper.parameter);

    while (true) {
        piccolo_yield();
    }
}

fn piccolo_create_task(task_func: task_function_t, parameter: ?*anyopaque) i32 {
    if (piccolo_ctx.task_count >= PICCOLO_OS_TASK_LIMIT)
        return -1;

    const tc = piccolo_ctx.task_count;

    task_wrappers[tc].function = task_func;
    task_wrappers[tc].parameter = parameter;

    piccolo_ctx.the_tasks[tc] =
        piccolo_os_create_task(@as([*]u32, @ptrCast(&piccolo_ctx.task_stacks[tc][0])), &task_wrapper_func);
    piccolo_ctx.task_count += 1;

    return @as(i32, @intCast(piccolo_ctx.task_count - 1));
}

const blinky = extern struct {
    delay: u32,
    message: [*:0]const u8,
};

const LED_PIN: u32 = 25;
const LED2_PIN: u32 = 14;

fn task1_func(param: ?*anyopaque) void {
    c.gpio_init(LED_PIN);
    c.gpio_set_dir(LED_PIN, true);

    var delay: u32 = 1000;
    var message: [*:0]const u8 = "nothing passed";

    if (param != null) {
        const blink_param = @as(*const blinky, @ptrCast(@alignCast(param)));
        delay = blink_param.delay;
        message = blink_param.message;
    }

    _ = c.printf("Message: %s\n", message);

    while (true) {
        _ = c.printf("ON");
        c.gpio_put(LED_PIN, true);
        c.sleep_ms(delay);
        _ = c.printf("OFF");
        c.gpio_put(LED_PIN, false);
        c.sleep_ms(delay);
    }
}

fn is_prime(n: u32) i32 {
    if ((n & 1) == 0 or n < 2) {
        return if (n == 2) 1 else 0;
    }

    var p: u32 = 3;
    while (p <= n / p) : (p += 2) {
        if (n % p == 0) {
            return 0;
        }
    }
    return 1;
}

fn task2_func(param: ?*anyopaque) void {
    var p: i32 = undefined;
    const prefix: [*:0]const u8 = if (param != null)
        @as([*:0]const u8, @ptrCast(param))
    else
        "Number";

    while (true) {
        const time_value = c.to_ms_since_boot(c.get_absolute_time());
        const masked_time = time_value & 0x7FFFFFFF;
        const safe_masked_time: u32 = masked_time & 0x7FFFFFFF;
        p = @as(i32, @bitCast(safe_masked_time));
        if (p >= 0 and is_prime(@as(u32, @intCast(p))) == 1) {
            _ = c.printf("%s: %d is prime!\n", prefix, p);
        }
    }
}

fn task3_cmpfunc(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
    const a_val = @as(*const i32, @ptrCast(@alignCast(a))).*;
    const b_val = @as(*const i32, @ptrCast(@alignCast(b))).*;
    return a_val - b_val;
}

fn task3_func(param: ?*anyopaque) void {
    c.gpio_init(LED2_PIN);
    c.gpio_set_dir(LED2_PIN, true);

    const message = if (param != null)
        @as([*:0]const u8, @ptrCast(param))
    else
        "No message provided";

    while (true) {
        c.gpio_put(LED2_PIN, true);
        _ = c.printf("Task 3 message: %s\n", message);

        var x: i32 = 0;
        while (x < 20) : (x += 1) {
            const values = @as([*c]i32, @ptrCast(@alignCast(c.malloc(1024 * @sizeOf(i32)))));
            var j: i32 = 1024;
            var i: usize = 0;
            while (i < 1024) : (i += 1) {
                values[i] = j;
                j -= 1;
            }
            _ = c.qsort(values, 1024, @sizeOf(i32), task3_cmpfunc);
            c.free(values);
        }
        c.gpio_put(LED2_PIN, false);
        c.sleep_ms(1000);
    }
}

export fn main() i32 {
    piccolo_init();

    _ = c.printf("PICCOLO OS Demo Starting...\n");

    const prime_prefix = "Prime number";
    const task3_message = "PLEASE";
    var blink = blinky{
        .delay = 1000,
        .message = "on of yee",
    };

    _ = piccolo_create_task(task1_func, &blink);
    _ = piccolo_create_task(task2_func, @ptrCast(@constCast(prime_prefix)));
    _ = piccolo_create_task(task3_func, @ptrCast(@constCast(task3_message)));
    piccolo_start();

    return 0; // Never gonna happen
}
