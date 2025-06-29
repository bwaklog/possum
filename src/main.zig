pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("hardware/gpio.h");
    @cInclude("hardware/spi.h");
    @cInclude("hardware/irq.h");
    @cInclude("hardware/timer.h");
});
const std = @import("std");
const shell = @import("shell/shell.zig");
const SD = @import("driver/sd.zig").SD;

const PICO_DEFAULT_LED_PIN = 25;
const SD_BLOCK_SIZE = 512;
const STACK_SIZE = 1024;
const TIME_SLICE_MS = 10;

//context is basically all registers so we sae them
const TaskContext = struct {
    r0: u32 = 0,
    r1: u32 = 0,
    r2: u32 = 0,
    r3: u32 = 0,
    r4: u32 = 0,
    r5: u32 = 0,
    r6: u32 = 0,
    r7: u32 = 0,
    r8: u32 = 0,
    r9: u32 = 0,
    r10: u32 = 0,
    r11: u32 = 0,
    r12: u32 = 0,
    sp: u32 = 0,
    lr: u32 = 0,
    pc: u32 = 0,
    psr: u32 = 0,
};

const TaskFunction = *const fn (ctx: *anyopaque) void;

const TaskState = enum {
    Ready,
    Running,
    Blocked,
    Finished,
};

//metadata for tasks
const Task = struct {
    id: u32,
    function: TaskFunction,
    context_data: *anyopaque,
    context: TaskContext,
    stack: [STACK_SIZE]u8,
    priority: u8,
    state: TaskState,
    time_slice: u32,
    remaining_time: u32,
    is_new: bool = true,
};

const MAX_TASKS = 8;
var tasks: [MAX_TASKS]Task = undefined;
var num_tasks: usize = 0;
var current_task_idx: usize = 0;
var scheduler_active: bool = false;
var need_schedule: bool = false;

//ready queue is just circular queue
const TaskQueue = struct {
    tasks: [MAX_TASKS]u32,
    front: usize = 0,
    rear: usize = 0,
    count: usize = 0,

    fn enqueue(self: *TaskQueue, task_id: u32) bool {
        if (self.count >= MAX_TASKS) return false;
        self.tasks[self.rear] = task_id;
        self.rear = (self.rear + 1) % MAX_TASKS;
        self.count += 1;
        return true;
    }

    fn dequeue(self: *TaskQueue) ?u32 {
        if (self.count == 0) return null;
        const task_id = self.tasks[self.front];
        self.front = (self.front + 1) % MAX_TASKS;
        self.count -= 1;
        return task_id;
    }

    fn isEmpty(self: *const TaskQueue) bool {
        return self.count == 0;
    }
};

//multiple qs for each priority
// TODO :make this dynamic and not hardcoded to 4

var ready_queues: [4]TaskQueue = [_]TaskQueue{TaskQueue{ .tasks = [_]u32{0} ** MAX_TASKS }} ** 4;

//cpu context saved
fn saveContext(ctx: *TaskContext) void {
    asm volatile (
        \\str r0, [%[ctx], #0]
        \\str r1, [%[ctx], #4]
        \\str r2, [%[ctx], #8]
        \\str r3, [%[ctx], #12]
        \\str r4, [%[ctx], #16]
        \\str r5, [%[ctx], #20]
        \\str r6, [%[ctx], #24]
        \\str r7, [%[ctx], #28]
        \\mov r0, r8
        \\str r0, [%[ctx], #32]
        \\mov r0, r9
        \\str r0, [%[ctx], #36]
        \\mov r0, r10
        \\str r0, [%[ctx], #40]
        \\mov r0, r11
        \\str r0, [%[ctx], #44]
        \\mov r0, r12
        \\str r0, [%[ctx], #48]
        \\mov r0, sp
        \\str r0, [%[ctx], #52]
        \\mov r0, lr
        \\str r0, [%[ctx], #56]
        \\mrs r0, xpsr
        \\str r0, [%[ctx], #64]
        :
        : [ctx] "r" (ctx),
        : "r0", "memory"
    );
}

fn restoreContext(ctx: *const TaskContext) void {
    asm volatile (
        \\ldr r0, [%[ctx], #0]
        \\ldr r1, [%[ctx], #4]
        \\ldr r2, [%[ctx], #8]
        \\ldr r3, [%[ctx], #12]
        \\ldr r4, [%[ctx], #16]
        \\ldr r5, [%[ctx], #20]
        \\ldr r6, [%[ctx], #24]
        \\ldr r7, [%[ctx], #28]
        \\ldr r0, [%[ctx], #32]
        \\mov r8, r0
        \\ldr r0, [%[ctx], #36]
        \\mov r9, r0
        \\ldr r0, [%[ctx], #40]
        \\mov r10, r0
        \\ldr r0, [%[ctx], #44]
        \\mov r11, r0
        \\ldr r0, [%[ctx], #48]
        \\mov r12, r0
        \\ldr r0, [%[ctx], #52]
        \\mov sp, r0
        \\ldr r0, [%[ctx], #56]
        \\mov lr, r0
        \\ldr r0, [%[ctx], #64]
        \\msr xpsr_nzcvq, r0
        \\ldr r0, [%[ctx], #60]  // Load PC
        \\bx r0                   // Jump to PC
        :
        : [ctx] "r" (ctx),
        : "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9", "r10", "r11", "r12", "lr", "memory"
    );
}

fn taskWrapper() callconv(.Naked) noreturn {
    asm volatile (
        \\mov r0, r0  
        \\blx lr     
        \\bl %[taskFinish] 
        :
        : [taskFinish] "i" (&taskFinish),
        : "r0", "lr"
    );
}

fn initTask(task_id: u32, function: TaskFunction, context_data: *anyopaque, priority: u8, time_slice: u32) bool {
    if (num_tasks >= MAX_TASKS) return false;

    //manually point the pc to task function, which is an opaque ptr to any function/task
    var task = &tasks[num_tasks];
    task.id = task_id;
    task.function = function;
    task.context_data = context_data;
    task.priority = priority;
    task.state = TaskState.Ready;
    task.time_slice = time_slice;
    task.remaining_time = time_slice;
    task.is_new = true;

    // downward growing stack
    const stack_top = @intFromPtr(&task.stack[STACK_SIZE - 1]);
    task.context.sp = stack_top;

    task.context.r0 = @intFromPtr(context_data);
    task.context.pc = @intFromPtr(&taskWrapper);
    task.context.lr = @intFromPtr(function);
    task.context.psr = 0x01000000; // Thumb mode

    num_tasks += 1;

    const priority_level = @min(priority, 3);
    _ = ready_queues[priority_level].enqueue(task_id);

    return true;
}

fn schedule() void {
    if (!scheduler_active) return;

    need_schedule = false;

    if (current_task_idx < num_tasks and tasks[current_task_idx].state == TaskState.Running) {
        saveContext(&tasks[current_task_idx].context);
        tasks[current_task_idx].state = TaskState.Ready;

        const priority_level = @min(tasks[current_task_idx].priority, 3);
        _ = ready_queues[priority_level].enqueue(tasks[current_task_idx].id);
    }

    var next_task_id: ?u32 = null;

    for (0..4) |i| {
        const priority = 3 - i;
        if (!ready_queues[priority].isEmpty()) {
            next_task_id = ready_queues[priority].dequeue();
            break;
        }
    }

    if (next_task_id) |task_id| {
        current_task_idx = task_id;
        tasks[current_task_idx].state = TaskState.Running;
        tasks[current_task_idx].remaining_time = tasks[current_task_idx].time_slice;

        _ = p.printf("Switching to task %d (priority %d)\n", task_id, tasks[current_task_idx].priority);

        if (tasks[current_task_idx].is_new) {
            tasks[current_task_idx].is_new = false;
            const task = &tasks[current_task_idx];

            const stack_ptr = @intFromPtr(&task.stack[STACK_SIZE - 1]);
            task.context.sp = stack_ptr;

            task.function(task.context_data);

            tasks[current_task_idx].state = TaskState.Finished;
            _ = p.printf("Task %d finished\n", task_id);
            need_schedule = true;
        } else {
            restoreContext(&tasks[current_task_idx].context);
        }
    } else {
        _ = p.printf("no ready tasks, sleep.......................................................................................\n");
        current_task_idx = MAX_TASKS;
    }
}

fn taskYield() void {
    if (current_task_idx < num_tasks) {
        need_schedule = true;
    }
}

fn taskFinish() void {
    if (current_task_idx < num_tasks) {
        tasks[current_task_idx].state = TaskState.Finished;
        _ = p.printf("Task %d finished\n", tasks[current_task_idx].id);
        need_schedule = true;
    }
}

const CounterTaskData = struct {
    start: u32,
    end: u32,
    current: u32,
};
//test programs
fn counterTask(ctx: *anyopaque) void {
    const data: *CounterTaskData = @ptrCast(@alignCast(ctx));

    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    while (data.current <= data.end) {
        _ = p.printf("Counter Task %d: %d\n", tasks[current_task_idx].id, data.current);
        data.current += 1;
        p.sleep_ms(300);
    }
}

fn blinkTask(ctx: *anyopaque) void {
    _ = ctx;

    var count: u32 = 0;
    while (count < 20) {
        p.gpio_put(PICO_DEFAULT_LED_PIN, true);
        p.sleep_ms(200);
        p.gpio_put(PICO_DEFAULT_LED_PIN, false);
        p.sleep_ms(200);

        count += 1;
        _ = p.printf("Blink count: %d\n", count);
    }
}

const fooTaskData = struct {
    num: u32,
    str: [*:0]const u8,
    time: u32,
};
fn foo(ctx: *anyopaque) void {
    const data: *fooTaskData = @ptrCast(@alignCast(ctx));
    _ = p.printf("Foo Task %d: %s, num: %d, time: %d\n", tasks[current_task_idx].id, data.str, data.num, data.time);

    while (data.num > 0) : (data.num -= 1) {
        p.gpio_put(PICO_DEFAULT_LED_PIN, true);
        _ = p.printf("%s\n", data.str);
        p.sleep_ms(data.time);
        p.gpio_put(PICO_DEFAULT_LED_PIN, false);
        _ = p.printf("%s\n", data.str);
        p.sleep_ms(data.time);
    }
}

export fn scheduler_interrupt(alarm_num: u32) callconv(.c) void {
    _ = alarm_num;

    if (scheduler_active and current_task_idx < num_tasks) {
        if (tasks[current_task_idx].remaining_time > TIME_SLICE_MS) {
            tasks[current_task_idx].remaining_time -= TIME_SLICE_MS;
        } else {
            need_schedule = true;
        }
    }
    //next intr
    const target_time = p.make_timeout_time_ms(TIME_SLICE_MS);
    _ = p.hardware_alarm_set_target(0, target_time);
}

export fn main() c_int {
    _ = p.stdio_init_all();

    p.gpio_init(PICO_DEFAULT_LED_PIN);
    p.gpio_set_dir(PICO_DEFAULT_LED_PIN, true);

    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);
    p.sleep_ms(50);
    p.gpio_put(PICO_DEFAULT_LED_PIN, false);
    p.sleep_ms(2000);
    p.gpio_put(PICO_DEFAULT_LED_PIN, true);

    _ = p.printf("*starting**\n");
    //the callback is to scheduler intr not to the task that needs to be run
    p.hardware_alarm_set_callback(0, scheduler_interrupt);

    var counter_data1 = CounterTaskData{ .start = 1, .end = 10, .current = 1 };
    var counter_data2 = CounterTaskData{ .start = 100, .end = 110, .current = 100 };
    var counter_data4 = CounterTaskData{ .start = 50, .end = 60, .current = 50 };

    var foo_data1 = fooTaskData{ .num = 5, .str = "ples", .time = 100 };
    var foo_data2 = fooTaskData{ .num = 3, .str = "hello", .time = 200 };

    _ = initTask(0, counterTask, &counter_data1, 2, 500);
    _ = initTask(1, blinkTask, undefined, 1, 400);
    _ = initTask(2, counterTask, &counter_data2, 1, 200);
    _ = initTask(3, foo, &foo_data1, 1, 100);
    _ = initTask(4, counterTask, &counter_data4, 4, 300);
    _ = initTask(5, foo, &foo_data2, 3, 200);

    scheduler_active = true;

    const target_time = p.make_timeout_time_ms(TIME_SLICE_MS);
    _ = p.hardware_alarm_set_target(0, target_time);

    schedule();

    while (true) {
        if (need_schedule) {
            schedule();
        } else {
            var all_finished = true;
            for (tasks[0..num_tasks]) |task| {
                if (task.state == TaskState.Ready or task.state == TaskState.Running) {
                    all_finished = false;
                    break;
                }
            }

            if (all_finished) {
                _ = p.printf("all tasks done\n");
                break;
            }
        }

        p.sleep_ms(10);
    }

    return 0;
}
