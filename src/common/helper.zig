const p = @import("common.zig").p;

pub fn check_control() void {
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

pub fn show_psp() void {
    var psp_val: u32 = undefined;
    asm volatile (
        \\ mrs %[value], psp
        : [value] "=r"  (psp_val)
    );
    _ = p.printf("[BAR TASK] psp address: %p\r\n", @as(*u32,@ptrFromInt(psp_val)));
}
