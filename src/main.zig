const std = @import("std");
const p = @import("common/common.zig").p;
const common = @import("common/common.zig");
const addr = @import("common/addrs.zig");
const task = @import("task/task.zig");
const shceduler = @import("scheduler/scheduler.zig");
const timer = @import("timer/timer.zig");

const init = @import("init.zig");

// ptr = @ptrFromInt(@intFromPtr(ptr)+0x21);

var sched = shceduler.Scheduler.new();
var sched_lock: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn lock_sched() void {
    while (sched_lock.swap(true, .acq_rel)) {
        // spin
    }
}
fn unlock_sched() void {
    sched_lock.store(false, .release);
}

fn uart_read_u32() u32 {
    var buf: [4]u8 = undefined;
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        var c: i32 = 0;
        while (true) {
            c = p.stdio_getchar_timeout_us(100_000);
            if (c != -1) break;
        }
        buf[i] = @intCast(c);
        _ = p.printf("[UART DEBUG] Read byte %d: 0x%02x\r\n", i, buf[i]);
    }
    return @as(u32, buf[0]) | (@as(u32, buf[1]) << 8) | (@as(u32, buf[2]) << 16) | (@as(u32, buf[3]) << 24);
}
fn uart_read_exact(buf: []u8) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        var c: i32 = 0;
        while (true) {
            c = p.stdio_getchar_timeout_us(100_000);
            if (c != -1) break;
        }
        buf[i] = @intCast(c);
    }
}
fn wait_for_keyword() void {
    _ = p.printf("INSIDE WAIT KEYOWRD");
    var buf: [9]u8 = undefined;
    while (true) {
        _ = p.scanf("%8s", &buf);
        if (std.mem.eql(u8, buf[0..8], "LOADPROG")) break;
    }
}

const ProgramData = struct {
    data: []u8,
    entry_offset: usize,
};

fn receive_program_over_uart_data() ?ProgramData {
    _ = p.printf("[CORE1] Waiting for LOADPROG keyword\r\n");
    var keyword_buf: [8]u8 = undefined;
    while (true) {
        _ = p.scanf("%8s", &keyword_buf);
        if (std.mem.eql(u8, &keyword_buf, "LOADPROG")) break;
    }
    _ = p.printf("[CORE1] LOADPROG received!\r\n");

    var size_buf: [8]u8 = undefined;
    uart_read_exact(size_buf[0..8]);
    const prog_size: usize = @intCast(std.mem.bytesToValue(u64, size_buf[0..8]));
    _ = p.printf("[CORE1] Program size: %d bytes\r\n", prog_size);

    if (prog_size == 0 or prog_size > 65536) {
        _ = p.printf("[CORE1] Invalid program size!\r\n");
        return null;
    }

    var entry_buf: [8]u8 = undefined;
    uart_read_exact(entry_buf[0..8]);
    const entry_offset: usize = @intCast(std.mem.bytesToValue(u64, entry_buf[0..8]));
    _ = p.printf("[CORE1] Entry offset: 0x%x\r\n", entry_offset);

    var prog_bytes: [65536]u8 = undefined;

    uart_read_exact(prog_bytes[0..prog_size]);
    _ = p.printf("[CORE1] Program received!\r\n");

    return ProgramData{
        .data = prog_bytes[0..prog_size],
        .entry_offset = entry_offset,
    };
}
fn interface_core1() callconv(.C) void {
    _ = p.stdio_init_all();
    _ = p.printf("HELLOFROMINTERFACE");
    // const ptr: *const fn (*anyopaque) void = @as(*const fn (*anyopaque) void, @ptrFromInt(0x20000021));

    // while (true) {
    //     wait_for_keyword();

    //     while (true) {
    //         const c = p.stdio_getchar_timeout_us(100_000);
    //         if (c != '\n' and c != '\r' and c != -1) {
    //             break;
    //         }
    //     }
    //     _ = p.printf("AFTER KEYWORD");
    //     _ = p.printf("[CORE1] LOADPROG received\r\n");

    //     const num_segments = uart_read_u32();
    //     _ = p.printf("[CORE1] num_segments = %d\r\n", num_segments);
    //     for (0..num_segments) |i| {
    //         const segment_addr = uart_read_u32();
    //         const size = uart_read_u32();
    //         _ = p.printf("[CORE1] segment_addr = 0x%x\r\n", segment_addr);
    //         _ = p.printf("[CORE1] size = %d\r\n", size);
    //         if (size > 4096) {
    //             _ = p.printf("[CORE1] segment too large\r\n");
    //             return;
    //         }
    //         var seg_buf: [4096]u8 = undefined;
    //         uart_read_exact(seg_buf[0..size]);
    //         std.mem.copyForwards(u8, @as([*]u8, @ptrFromInt(segment_addr))[0..size], seg_buf[0..size]);

    //         _ = p.printf("\r\n=== [CORE1] SEGMENT RECEIVED ===\r\n");
    //         _ = p.printf("[CORE1] Segment %d: addr=0x%x, size=%d, data=", i, segment_addr, size);
    //         const print_len = if (size < 8) size else 8;
    //         for (seg_buf[0..print_len]) |b| {
    //             _ = p.printf("%02x ", b);
    //         }
    //         _ = p.printf("===\r\n");
    //     }
    // const entry = uart_read_u32();
    // _ = p.printf("[CORE1] Adding new task at 0x%x\r\n", entry);
    // _ = p.printf("before lock\r\n");
    // lock_sched();
    // _ = p.printf("after lock\r\n");
    // // const entry_fn: *const fn (*anyopaque) void = @ptrFromInt(entry);
    // _ = p.printf("WELL ENTRY:");
    // // _ = p.printf(@intFromPtr(entry_fn));
    // _ = p.printf("before create task\r\n");
    // sched.create_task(new_task, null, 0);
    // _ = p.printf("after task create\r\n");
    // unlock_sched();
    // _ = p.printf("unlcoked\r\n");
    // ...inside interface_core1...
    // var prog_ptr = receive_program_over_uart();
    // if (prog_ptr != null) {
    //     _ = p.printf("[CORE1] Program loaded at ptr: 0x%x\r\n", @intFromPtr(prog_ptr));
    // }
    _ = p.printf("BEFORE EMBED TASK\r\n");
    // const ptr: *const fn (*anyopaque) void = @as(*const fn (*anyopaque) void, @ptrFromInt(@intFromPtr(@embedFile("test.elf")) + 0x0000018e));
    while (true) {
        const prog_data_opt = receive_program_over_uart_data();
        if (prog_data_opt) |prog_data| {
            const prog_ptr: *const fn (*anyopaque) void = @as(*const fn (*anyopaque) void, @ptrFromInt(@intFromPtr(&prog_data.data[0]) + prog_data.entry_offset));
            sched.create_task(prog_ptr, null, 0);
            // unlock_sched();
        } else {
            _ = p.printf("[CORE1] Failed to load program over UART\r\n");
        }
    }
    // lock_sched();
    // sched.create_task(prog_ptr, null, 0);
    // unlock_sched();
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
    // p.sleep_ms(1000000);
    _ = p.printf("AFTER LAUNCH");
    lock_sched();
    sched.create_task(foo_task, null, 0);
    // sched.create_task(bar_task, null, 0);
    // sched.create_task(baz_task, null, 0);
    unlock_sched();
    p.sleep_ms(500);
    _ = p.printf("initialised tasks\r\n");

    var dummy_stack = [_]u32{0} ** 32;
    common.task_init_stack(&dummy_stack[0]);

    sched.current_task = 0;

    while (true) {
        lock_sched();
        timer.systick_config(common.TIME_SLICE);
        sched.tasks[sched.current_task].stack_start = common.pre_switch(sched.tasks[sched.current_task].stack_start);
        sched.next();
        unlock_sched();

        // p.sleep_ms(500);
        _ = p.printf("[DEBUG] Switch back to MSP, outside of task\r\n");
    }
    return 0;
}
