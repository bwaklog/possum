const p = @import("common/common.zig").p;
const common = @import("common/common.zig");

/// initlise the sdk stdio along with setting the priority
/// to the lowest for system handler priority registers
pub fn init() void {
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
        @as(
            [*c]p.io_rw_32, 
            @ptrFromInt(p.PPB_BASE + p.M0PLUS_SHPR2_OFFSET)
        ),
        p.M0PLUS_SHPR2_BITS
    );

    p.hw_set_bits(
        @as(
            [*c]p.io_rw_32, 
            @ptrFromInt(p.PPB_BASE + p.M0PLUS_SHPR3_OFFSET)
        ),
        p.M0PLUS_SHPR3_BITS
    );
}
