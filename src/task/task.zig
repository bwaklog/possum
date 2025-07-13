const p = @import("../common/common.zig").p;
const common = @import("../common/common.zig"); 

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
