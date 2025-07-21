const p = @import("../common/common.zig").p;
const common = @import("../common/common.zig");
const addr = @import("../common/addrs.zig");

pub const SysTick = struct {
    unit: u32,

    const Self = @This();

    pub fn new(unit: c_ulong) Self {
        const systick = SysTick {
            .unit = unit,
        };

        return systick;
    }

    pub inline fn disable(self: *Self) void {
        _ = self;
        addr.SYST_CSR.* = 0;
        asm volatile (
            \\ dsb
        );
        asm volatile (
            \\ isb
        );
    }

    pub inline fn set_systick(self: *Self, unit: c_ulong) void {
        _ = self;
        p.hw_set_bits(
            @as([*c]p.io_rw_32, @ptrFromInt(p.PPB_BASE + p.M0PLUS_ICSR_OFFSET)),
            p.M0PLUS_ICSR_PENDSTCLR_BITS,
        );

        addr.SYST_RVR.* = unit - 1;
        addr.SYST_CVR.* = 0;

        // Bits[2] = 0 -> Use reference clock
        // Bits[1] = 1 -> Set intr status to pending at 0
        // Bits[0] = 1 -> Set the clock to count down
        addr.SYST_CSR.* = 0b011;
    }

    pub inline fn set_with_config(self: *Self) void {
        self.set_systick(self.unit);
    }
};

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
