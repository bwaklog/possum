const p = @import("../common/common.zig").p;
const common = @import("../common/common.zig");
const addr = @import("../common/addrs.zig");

pub fn systick_config(n: c_ulong) void {
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
