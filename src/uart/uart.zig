const std = @import("std");
const p = @import("../common/common.zig").p;
const common = @import("../common/common.zig");
const addr = @import("../common/addrs.zig");

pub fn uart_read_u32() u32 {
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

pub fn uart_read_exact(buf: []u8) void {
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
