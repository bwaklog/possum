pub const PPB_BASE: u32 = 0xe0000000;
pub const SHPR2_OFFSET: u32 = 0x0000ed1c;
pub const SHPR2_BITS: u32 = 0xc0000000;
pub const SHPR3_OFFSET: u32 = 0x0000ed20;
pub const SHPR3_BITS: u32 = 0xc0c00000;
pub const M0PLUS_ICSR_OFFSET: u32 = 0x0000ed04;
pub const M0PLUS_ICSR_BITS: u32 = 0x9edff1ff;

// SysTick Register Addresses
pub const SYST_CSR: *u32 = @ptrFromInt(0xE000E010);
pub const SYST_RVR: *u32 = @ptrFromInt(0xE000E014);
pub const SYST_CVR: *u32 = @ptrFromInt(0xE000E018);
pub const SYST_Calib: *u32 = @ptrFromInt(0xE000E01C);
