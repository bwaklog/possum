pub const p = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("pico/stdlib.h");
    @cInclude("pico/time.h");
    @cInclude("hardware/structs/systick.h");
    @cInclude("hardware/sync.h");
    @cInclude("pico/multicore.h");
});

pub const generic_func  = *const fn(ctx: *anyopaque) void;
pub const TIME_SLICE: u32 = 1_250_000; // ms value

pub const TOTAL_TASKS: usize = 10;
pub const PSTACK_SIZE: usize = 256;

// assembly method definitions
pub extern fn foo(a: u32, b: u32) u32; // DEBUG
pub extern fn task_init_stack(n: *u32) void;
pub extern fn pre_switch(n: *u32) *u32;
