const std = @import("std");
const p = @import("../common/common.zig").p;
const common = @import("../common/common.zig"); 
const uart = @import("../uart/uart.zig");

pub const Task = struct {
    callback: common.generic_func,
    data: ?*anyopaque,
    stack_start: *u32,
    priority: usize,

    const Self = @This();

    pub fn new(
        task_func: common.generic_func, 
        data: ?*anyopaque, 
        stack_start: *u32,
        priority: usize,
    ) Task {
        return Task {
            .callback = task_func,
            .data = data,
            .stack_start = stack_start,
            .priority = priority,
        };
    }
};

pub const ProgramData = struct {
    data: [*]u8,
    entry_offset: usize,
};

pub fn receive_program_uart() ?ProgramData {
    _ = p.printf("[CORE1] Waiting for LOADPROG keyword\r\n");
    var keyword_buf: [8]u8 = undefined;
    while (true) {
        _ = p.scanf("%8s", &keyword_buf);
        if (std.mem.eql(u8, &keyword_buf, "LOADPROG")) break;
    }
    _ = p.printf("[CORE1] LOADPROG received!\r\n");

    var size_buf: [8]u8 = undefined;
    uart.uart_read_exact(size_buf[0..8]);
    const prog_size: usize = @intCast(std.mem.bytesToValue(u64, size_buf[0..8]));
    _ = p.printf("[CORE1] Program size: %d bytes\r\n", prog_size);

    if (prog_size == 0 or prog_size > 65536) {
        _ = p.printf("[CORE1] Invalid program size!\r\n");
        return null;
    }

    var entry_buf: [8]u8 = undefined;
    uart.uart_read_exact(entry_buf[0..8]);
    const entry_offset: usize = @intCast(std.mem.bytesToValue(u64, entry_buf[0..8]));
    _ = p.printf("[CORE1] Entry offset: 0x%x\r\n", entry_offset);

    // var prog_bytes: [65536]u8 = undefined;
    const prog_bytes_alloc = p.malloc(prog_size);
    if (prog_bytes_alloc) |prog_bytes_heap| {
        var prog_bytes: [*]u8 = @ptrCast(@alignCast(prog_bytes_heap));
        uart.uart_read_exact(prog_bytes[0..prog_size]);
        _ = p.printf("[CORE1] Program received!\r\n");

        return ProgramData{
            .data = prog_bytes,
            .entry_offset = entry_offset,
        };
    }

    return null;
}
