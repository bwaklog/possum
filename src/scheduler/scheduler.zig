const std = @import("std");
const p = @import("../common/common.zig").p;
const common = @import("../common/common.zig");
const task = @import("../task/task.zig");

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

pub const Scheduler = struct {
    stacks: [common.TOTAL_TASKS][common.PSTACK_SIZE]u32,
    // tasks: [TOTAL_TASKS]*u32,
    tasks: [common.TOTAL_TASKS]task.Task,

    task_count: usize,
    current_task: usize,

    scheduler_lock: std.atomic.Value(bool),

    const Self = @This();

    pub fn new() Self {
        const ret = Scheduler {
            .stacks = .{.{0} ** common.PSTACK_SIZE} ** common.TOTAL_TASKS,
            .tasks = undefined,
            .task_count = 0,
            .current_task = 0,
            .scheduler_lock = std.atomic.Value(bool).init(false),
        };

        return ret;
    }

    pub fn create_task(
        self: *Self, 
        task_func: common.generic_func, 
        data: ?*anyopaque,
        priority: usize
    ) void {
        // we mimick the stack frame
        // 256 - 17 -> how much we are pushing to the stack
        const offset: usize = common.PSTACK_SIZE - 17;

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
        
        const new_task = task.Task.new(task_func, data, &self.stacks[n][offset], priority);
        self.tasks[n] = new_task;
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

    // scheduler locking
    pub fn lock(self: *Self) void {
        while (self.scheduler_lock.swap(true, .acq_rel)) {
            // spin
        }
    }

    pub fn unlock(self: *Self) void {
        self.scheduler_lock.store(false, .release);
    }
};
