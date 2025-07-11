pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("pico/time.h");
    @cInclude("hardware/structs/systick.h");
    @cInclude("hardware/sync.h");
});

pub const addr = @import("addr/hw_addr.zig");

const generic_func  = *const fn(ctx: *anyopaque) void;
const TIME_SLICE: u32 = 2_000; // ms value

const REG_ALIAS_SET_BITS = 0x2 << 12;

// assembly method definitions
extern fn foo(a: u32, b: u32) u32; // DEBUG
extern fn task_init_stack(n: *u32) void;
extern fn pre_switch(n: *u32) *u32;

const Task = struct {
    callback: generic_func,
    data: ?*anyopaque,
    stack_start: *u32,

    const Self = @This();

    fn new(
        task_func: generic_func, 
        data: ?*anyopaque, 
        stack_start: *u32
    ) Task {
        return Task {
            .callback = task_func,
            .data = data,
            .stack_start = stack_start,
        };
    }

    // fn get_stack(self: *Self) *u32 {
    // }
};

const TOTAL_TASKS: usize = 10;
const PSTACK_SIZE: usize = 256;

/// NOTE (from the arm docs)
/// when the processor takes an exception (tail chained 
/// or if its late arrival) it pushes the following onto
/// the stack (going down memory addresses)
///
/// ```
/// <previous>
/// SP + 0x1c xPSR
/// SP + 0x18 PC (R15) -> next instr of the interrupted 
///                       program
/// SP + 0x14 LR (R14)
/// SP + 0x10 R12 <- intra procedure call
/// SP + 0x0c R3
/// SP + 0x08 R2
/// SP + 0x04 R1
/// SP + 0x00 R0 <- this is where SP will be at the intr.
/// ```
///
/// hence the hardware already saves these parts for us,
/// while servicing an interrupt, for a context switch 
/// we would need to store the remaining R4-R11(FP) to 
/// be pushed onto the stack
///
/// while the processor executes the except. handler
/// it writes the EXC_RETURN address to LR, which 
/// signifies which SP corresponds to the stack frame
/// and the opr. mode of the processor
///
/// the EXC_RETURN value is used by the processor to            
/// check if it has completed an exception. [31:4] bits        
/// being 0xFFFFFFF, when loaded to PC, its not a regular
/// branch opr, rather exception is complete
///     
///     0xFFFFFFF1 -> ret to handler, MSP used and state 
///                   is retrieved from MSP
///     0xFFFFFFF9 -> ret to thread, MSP used and state 
///                   is retrieved from MSP
///
///   **0xFFFFFFFD -> ret to handler, PSP used and state 
///                   is retrieved from PSP
///
/// from `src/switch.s` the pop {pc} attempts to load
/// 0xFFFFFFFD into the pc
///

const Sched = struct {
    stacks: [TOTAL_TASKS][PSTACK_SIZE]u32,
    // tasks: [TOTAL_TASKS]*u32,
    tasks: [TOTAL_TASKS]Task,

    task_count: usize,
    current_task: usize,

    const Self = @This();

    pub fn new() Self {
        const ret = Sched {
            .stacks = .{.{0} ** PSTACK_SIZE} ** TOTAL_TASKS,
            .tasks = undefined,
            .task_count = 0,
            .current_task = 0,
        };

        return ret;
    }

    pub fn create_task(self: *Self, task_func: generic_func, data: ?*anyopaque) void {
        // we mimick the stack frame
        // 256 - 17 -> how much we are pushing to the stack
        const offset: usize = PSTACK_SIZE - 17;

        const n = self.task_count;

        // return to thread mode with PSP
        self.stacks[n][offset + 8] = 0xFFFFFFFD;
        self.stacks[n][offset + 15] = @as(u32, @intFromPtr(task_func));

        // PSR thumb bit
        // SPSEL bit [1] of CONTROL reg defines the stack to
        // be used
        //      - 0 = MSP
        //      - 1 = PSP
        // "In Handler mode this bit reads as zero and ignores 
        // writes."
        self.stacks[n][offset + 16] = 0x01000000;
        
        const task = Task.new(task_func, data, &self.stacks[n][offset]);
        self.tasks[n] = task;
        // self.tasks[n] = &self.stacks[n][offset];

        self.task_count += 1;

        // this should be the PSP
        _ = p.printf("base addr of task %d: %p\r\n", n, &self.tasks[n]);
        //
        // const excep_ret: *u32 = @ptrFromInt(@intFromPtr(self.tasks[n]) + @sizeOf(u32) * 8);
        // _ = p.printf("exception return addr for task %p\r\n", excep_ret.*);
    }

    pub fn next(self: *Self) void {
        self.current_task = (self.current_task + 1) % self.task_count;
        // return self.tasks[self.current_task];
    }
};

fn busy_wait(us: u32) void {
    const end = p.time_us_32() + us;
    while (p.time_us_32() < end) {}
}

fn check_control() void {
    var result: u32 = undefined;
    asm volatile (
        \\ mrs %[result], control
        : [result] "=r" (result)
    );

    if ((result & 0x2) == 0x2) {
        _ = p.printf("[DEBUG] : in PSP\r\n");
    } else {
        _ = p.printf("[DEBUG] : in MSP\r\n");
    }
}

var sched = Sched.new();

fn systick_config(n: c_ulong) void {
    addr.SYST_CSR.* = 0;
    asm volatile (
        \\ dsb
    );
    asm volatile (
        \\ isb
    );

    p.hw_set_bits(
        @as([*c]p.io_rw_32, @ptrFromInt(p.PPB_BASE + p.M0PLUS_ICSR_OFFSET)), 
        p.M0PLUS_ICSR_PENDSTCLR_BITS
    );

    addr.SYST_RVR.* = n - 1;
    addr.SYST_CVR.* = 0;
    addr.SYST_CSR.* = 0b011;
}

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
        // var psp_val: u32 = undefined;
        // asm volatile (
        //     \\ mrs %[value], psp
        //     : [value] "=r"  (psp_val)
        // );
        // _ = p.printf("[BAR TASK] psp address: %p\r\n", @as(*u32,@ptrFromInt(psp_val)));

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

    _ = p.printf("finished boot wait\n");

    p.hw_set_bits(
        @as([*c]p.io_rw_32, @ptrFromInt(p.PPB_BASE + p.M0PLUS_SHPR2_OFFSET)),
        p.M0PLUS_SHPR2_BITS
    );

    p.hw_set_bits(
        @as([*c]p.io_rw_32, @ptrFromInt(p.PPB_BASE + p.M0PLUS_SHPR3_OFFSET)),
        p.M0PLUS_SHPR3_BITS
    );

    sched.create_task(foo_task, null);
    sched.create_task(bar_task, null);
    sched.create_task(baz_task, null);

    _ = p.printf("initialised tasks\r\n");

    var dummy_stack = [_]c_uint{0} ** 32;
    task_init_stack(&dummy_stack[0]);

    sched.current_task = 0;

    while (true) {

        _ = p.printf("start of loop\r\n");

        systick_config(125000);

        sched.tasks[sched.current_task].stack_start = pre_switch(sched.tasks[sched.current_task].stack_start);
        sched.next();

        _ = p.printf("[DEBUG] Switch back to MSP, outside of task\r\n");
    }

    return 0;
}
