pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    // PICO W specific header
    @cInclude("hardware/timer.h");
    @cInclude("hardware/watchdog.h");
    @cInclude("hardware/irq.h");
    @cInclude("setjmp.h");
    @cInclude("pico/time.h");

    @cInclude("hardware/structs/systick.h");
    @cInclude("hardware/sync.h");
});

// pub const cticks = @cImport({
//     @cInclude("priority.h");
// });

// const generic_func  = *fn(*anyopaque) ?*anyopaque;
const generic_func  = *const fn(ctx: *anyopaque) void;
const TIME_SLICE: u32 = 2_000; // ms value

const PPB_BASE: u32 = 0xe0000000;
const SHPR2_OFFSET: u32 = 0x0000ed1c;
const SHPR2_BITS: u32 = 0xc0000000;
const SHPR3_OFFSET: u32 = 0x0000ed20;
const SHPR3_BITS: u32 = 0xc0c00000;
const M0PLUS_ICSR_OFFSET: u32 = 0x0000ed04;
const M0PLUS_ICSR_BITS: u32 = 0x9edff1ff;

const SYST_CSR: *u32 = @ptrFromInt(0xE000E010);
const SYST_RVR: *u32 = @ptrFromInt(0xE000E014);
const SYST_CVR: *u32 = @ptrFromInt(0xE000E018);
const SYST_Calib: *u32 = @ptrFromInt(0xE000E01C);

const REG_ALIAS_SET_BITS = 0x2 << 12;

// assembly method definitions
extern fn foo(a: u32, b: u32) u32; // DEBUG
extern fn isr_svcall(void) void;
extern fn isr_systick(void) void;
extern fn task_init_stack(n: *u32) void;
extern fn pre_switch(n: *u32) void;

// extern fn yield(void) void;
// extern fn syscall(void) void;

// const Task = struct {
//     callback: generic_func,
//     data: ?*anyopaque,
//
//     fn new(task_func: generic_func, data: *anyopaque) Task {
//         return Task {
//             .callback = task_func,
//             .data = data,
//         };
//     }
// };

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
    tasks: [TOTAL_TASKS]*u32,

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

    pub fn create_task(self: *Self, task: generic_func) void {
        // we mimick the stack frame
        // 256 - 17 -> how much we are pushing to the stack
        const offset: usize = PSTACK_SIZE - 17;

        // _ = p.printf("task func is at %p\r\n", @as(u32, @intFromPtr(task)));

        const n = self.task_count;

        // return to thread mode with PSP
        self.stacks[n][offset + 8] = 0xFFFFFFFD;
        self.stacks[n][offset + 15] = @as(u32, @intFromPtr(task));

        // PSR thumb bit
        // SPSEL bit [1] of CONTROL reg defines the stack to
        // be used
        //      - 0 = MSP
        //      - 1 = PSP
        // "In Handler mode this bit reads as zero and ignores 
        // writes."
        self.stacks[n][offset + 16] = 0x01000000;
        
        self.tasks[n] = &self.stacks[n][offset];

        self.task_count += 1;

        // this should be the PSP
        _ = p.printf("base addr of task %d: %p\r\n", n, &self.tasks[n]);
        //
        // const excep_ret: *u32 = @ptrFromInt(@intFromPtr(self.tasks[n]) + @sizeOf(u32) * 8);
        // _ = p.printf("exception return addr for task %p\r\n", excep_ret.*);
    }

    pub fn re_create_task(self: *Self, task: generic_func, pos: usize) void {
        // we mimick the stack frame
        // 256 - 17 -> how much we are pushing to the stack
        const offset: usize = PSTACK_SIZE - 17;


        // return to thread mode with PSP
        self.stacks[pos][offset + 8] = 0xFFFFFFFD;
        self.stacks[pos][offset + 15] = @as(u32, @intFromPtr(task));

        // PSR thumb bit
        // SPSEL bit [1] of CONTROL reg defines the stack to
        // be used
        //      - 0 = MSP
        //      - 1 = PSP
        // "In Handler mode this bit reads as zero and ignores 
        // writes."
        self.stacks[pos][offset + 16] = 0x01000000;
        
        self.tasks[pos] = &self.stacks[pos][offset];

        self.task_count += 1;
    }


    pub fn next(self: *Self) *u32 {
        self.current_task = (self.current_task + 1) % self.task_count;
        return self.tasks[self.current_task];
        // return self.tasks[0];
    }
};

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

fn sched_callback(alarm_num: c_uint) callconv(.c) void {
    _ = alarm_num;

    var psp_val: u32 = undefined;
    asm volatile (
        \\ mrs %[value], psp
        : [value] "=r"  (psp_val)
    );
    // _ = p.printf("old psp: %p\r\n", @as(*u32,@ptrFromInt(psp_val)));

    asm volatile(
        \\ mrs r0, psp
        \\ 
        \\ subs r0, #4
        \\ str r1, [r0]
        \\ subs r0, #16
        \\ stmia r0!, {r4-r7}
        \\
        \\ mov r4, r8
        \\ mov r5, r9
        \\ mov r6, r10
        \\ mov r7, r11
        \\ subs r0, #32
        \\ stmia r0!, {r4-r7}
        \\ subs r0, #16
        // \\
        // \\ pop {r1, r2, r3, r4, r5}
        // \\ mov r8, r1
        // \\ mov r9, r2
        // \\ mov r10, r3
        // \\ mov r11, r4
        // \\ mov r12, r5 /* r12 is ip */
        // \\ pop {r4, r5, r6, r7}       
        // \\                             
        // \\ msr xpsr_nzcvq, ip
    );

    _ = p.printf("switched state in callback\r\n");

    // _ = p.printf("[DEBUG] sched_callback running %d\r\n", alarm_num);
    // _ = p.printf("[DEBUG] does not hit this line\r\n", alarm_num);
    // const time  = p.time_us_64();
    // _ = p.printf("[DEBUG][TIMER %d] walker callback at %lld\r\n", alarm_num, time);
    // sched.re_create_task(foo_task, 0);

    const task_ptr = sched.next();

    const timeout = p.make_timeout_time_ms(TIME_SLICE);
    _ = p.hardware_alarm_set_target(0, timeout);
    
    pre_switch(task_ptr);

    _ = p.printf("called pre_switch\r\n");

    // asm volatile (
    //     \\ mrs %[value], psp
    //     : [value] "=r"  (psp_val)
    // );
    // _ = p.printf("new psp: %p\r\n", @as(*u32,@ptrFromInt(psp_val)));

 //    asm volatile(
 //        \\ ldmia r0!,{r1}
 //        \\ mov lr, r1
	// \\ msr psp, r0
 //    );
    
    // return true;
    // _ = p.printf("[DEBUG] timer couldnt find user data");
    // return true;
}

fn set_interrupt_priority() void {

}

fn systick_config(n: c_ulong) void {
    SYST_CSR.* = 0;
    asm volatile (
        \\ dsb
    );
    asm volatile (
        \\ isb
    );

    p.hw_set_bits(
        @ptrFromInt(@as(u32, p.PPB_BASE + p.M0PLUS_ICSR_OFFSET)), 
        p.M0PLUS_ICSR_PENDSTCLR_BITS
    );

    SYST_RVR.* = n - 1;
    SYST_CVR.* = 0;
    SYST_CSR.* = 0b101;
}

// custom function
const foo_data = struct {};
fn foo_task(ctx: *anyopaque) void {
    var i: c_uint = 0;
    _ = ctx;

    while (true) {
        _ = p.printf("[FOO TASK]: hello %d!\r\n", i);
        const cur_systick_val = p.systick_hw.*.cvr;
        _ = p.printf("[DEBUG][FOO TASK] testing systick %u\r\n", cur_systick_val);

        // var psp_val: u32 = undefined;
        // asm volatile (
        //     \\ mrs %[value], psp
        //     : [value] "=r"  (psp_val)
        // );
        // _ = p.printf("[FOO TASK] psp address: %p\r\n", @as(*u32,@ptrFromInt(psp_val)));

        i += 1;
        p.gpio_put(25, true);
        p.sleep_ms(200);
        p.gpio_put(25, false);
        p.sleep_ms(200);
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
        p.sleep_ms(500);
    }
}

fn repeating_timer_callback(timer: [*c]p.repeating_timer_t) callconv(.c) bool {

    _ = p.printf("[DEBUG] inside sched_callback\r\n");

    // var psp_val: u32 = undefined;
    // asm volatile (
    //     \\ mrs %[value], psp
    //     : [value] "=r"  (psp_val)
    // );
    // _ = p.printf("[DEBUG][callback] psp address: %p\r\n", @as(*u32,@ptrFromInt(psp_val)));

    
    // _ = p.printf("[DEBUG] sched_callback running %d\r\n", timer.*.alarm_id);
    // _ = p.printf("[DEBUG] does not hit this line\r\n");
    const time  = p.time_us_64();
    _ = p.printf("[DEBUG][TIMER %d] walker callback at %lld\r\n", timer.*.alarm_id, time);
    _ = p.printf("[DEBUG] does not hit this line??\r\n");

    // sched.re_create_task(foo_task, 0);

    // const task_ptr = sched.next();

    // const timeout = p.make_timeout_time_ms(5000);
    // _ = p.hardware_alarm_set_target(0, timeout);
    
    // pre_switch(task_ptr);
    
    // return true;
    // _ = p.printf("[DEBUG] timer couldnt find user data");
    // return true;

    return true;
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
        @ptrFromInt(@as(u32, p.PPB_BASE + p.M0PLUS_SHPR2_OFFSET)), 
        p.M0PLUS_SHPR2_BITS
    );

    p.hw_set_bits(
        @ptrFromInt(@as(u32, p.PPB_BASE + p.M0PLUS_SHPR3_OFFSET)), 
        p.M0PLUS_SHPR3_BITS
    );

    sched.create_task(foo_task);
    sched.create_task(bar_task);
    sched.create_task(baz_task);

    _ = p.printf("initialised tasks\r\n");

    var dummy_stack = [_]c_uint{0} ** 32;
    task_init_stack(&dummy_stack[0]);

    sched.current_task = 0;

    var current_task: usize = 0;
    while (true) {

        _ = p.printf("start of loop\r\n");

        systick_config(100000);
        // SYST_CSR.* = 0;
        //
        // p.hw_set_bits(
        //     @ptrFromInt(@as(u32, p.PPB_BASE + p.M0PLUS_ICSR_OFFSET)), 
        //     p.M0PLUS_ICSR_PENDSTCLR_BITS
        // );
        //
        // SYST_RVR.* = 10000 - 1;
        // SYST_CVR.* = 10000 - 1;
        // SYST_CSR.* = 0b01;

        _ = p.printf("switching to task %d\r\n", current_task);

        pre_switch(sched.tasks[current_task]);

        _ = p.printf("[DEBUG] Switch back to MSP, outside of task\r\n");
        // current_task = @mod(current_task + 1, sched.task_count);
        current_task = 0;
        _ = p.printf("[DEBUG] current_task now at %d\r\n", current_task);

        // _ = p.printf("[DEBUG] asjdhkjsa\r\n");
        // _ = p.printf("[DEBUG] testing systick %u\r\n", cur_systick_val);
        // p.sleep_ms(250);
        // systick_config(3000);
        // _ = p.printf("systick config set\r\n");
        // pre_switch(sched.tasks[0]);
        //
        // sched.current_task = (sched.current_task + 1) % sched.task_count;
    }

    return 0;
}
