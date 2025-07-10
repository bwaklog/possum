const std = @import("std");
const builtin = @import("builtin");

const Board = .pico;
const Platform = .rp2040;

const StdioUsb = true;
const PicoStdlibDefine = if (StdioUsb) "LIB_PICO_STDIO_USB" else "LIB_PICO_STDIO_UART";

const PicoSDKPath: ?[]const u8 = null;
const ARMNoneEabiPath: ?[]const u8 = null;

pub fn build(b: *std.Build) anyerror!void {
    const target_query = std.Target.Query{
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
    };

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addObject(.{
        .name = "zig-pico",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
    });

    const pico_sdk_path =
        if (PicoSDKPath) |sdk_path| sdk_path else std.process.getEnvVarOwned(b.allocator, "PICO_SDK_PATH") catch null orelse {
            std.log.err("PICO_SDK_PATH not set", .{});
            return;
        };
    const pico_init_cmake_path = b.pathJoin(&.{ pico_sdk_path, "pico_sdk_init.cmake" });

    std.fs.cwd().access(pico_init_cmake_path, .{}) catch {
        std.log.err(
            \\Provided Pico SDK path does not contain the file pico_sdk_init.cmake
            \\Tried: {s}
            \\Are you sure you entered the path correctly?"
        , .{pico_init_cmake_path});
        return;
    };

    lib.linkLibC();

    const arm_header_location = blk: {
        if (std.process.getEnvVarOwned(b.allocator, "ARM_NONE_EABI_PATH") catch null) |path| {
            break :blk path;
        }

        break :blk error.StandardHeaderLocationNotSpecified;
    } catch |err| {
        err catch {};
        std.log.err("could not determine ARM_NONE_EABI_PATH for heaaders", .{});
        return;
    };
    lib.addSystemIncludePath(.{ .cwd_relative = arm_header_location });

    const board_header = blk: {
        const header_file = @tagName(Board) ++ ".h";
        const _board_headers = b.pathJoin(&.{ pico_sdk_path, "src/boards/include/boards", header_file });

        std.fs.cwd().access(_board_headers, .{}) catch {
            std.log.err("could not find header file for board {s}\n", .{@tagName(Board)});
            return;
        };

        break :blk header_file;
    };

    const header_str = try std.fmt.allocPrint(b.allocator,
        \\#include "{s}/src/boards/include/boards/{s}"
        \\#include "{s}/src/rp2_common/cmsis/include/cmsis/rename_exceptions.h"
    , .{ pico_sdk_path, board_header, pico_sdk_path });

    // Write and include the generated header
    const config_autogen_step = b.addWriteFile("pico/config_autogen.h", header_str);
    lib.step.dependOn(&config_autogen_step.step);
    lib.addIncludePath(config_autogen_step.getDirectory());

    // requires running cmake at least once
    lib.addSystemIncludePath(b.path("build/generated/pico_base"));

    const pico_sdk_includes = [_][]const u8{
        "/src/common/pico_binary_info/include",
        "/src/common/boot_picoboot_headers/include",
        "/src/common/pico_util/include",
        "/src/common/boot_picobin_headers/include",
        "/src/common/pico_stdlib_headers/include",
        "/src/common/hardware_claim/include",
        "/src/common/pico_time/include",
        "/src/common/pico_bit_ops_headers/include",
        "/src/common/pico_usb_reset_interface_headers/include",
        "/src/common/pico_base_headers/include",
        "/src/common/pico_sync/include",
        "/src/common/pico_divider_headers/include",
        "/src/common/boot_uf2_headers/include",
        "/src/rp2_common/hardware_exception/include",
        "/src/rp2_common/hardware_powman/include",
        "/src/rp2_common/pico_malloc/include",
        "/src/rp2_common/pico_multicore/include",
        "/src/rp2_common/hardware_i2c/include",
        "/src/rp2_common/hardware_riscv_platform_timer/include",
        "/src/rp2_common/hardware_sync/include",
        "/src/rp2_common/hardware_irq/include",
        "/src/rp2_common/hardware_gpio/include",
        "/src/rp2_common/hardware_interp/include",
        "/src/rp2_common/pico_bootrom/include",
        "/src/rp2_common/hardware_uart/include",
        "/src/rp2_common/hardware_timer/include",
        "/src/rp2_common/hardware_base/include",
        "/src/rp2_common/hardware_rcp/include",
        "/src/rp2_common/hardware_pio/include",
        "/src/rp2_common/pico_btstack/include",
        "/src/rp2_common/hardware_pll/include",
        "/src/rp2_common/pico_stdio_rtt/include",
        "/src/rp2_common/pico_stdio_semihosting/include",
        "/src/rp2_common/hardware_clocks/include",
        "/src/rp2_common/pico_lwip/include",
        "/src/rp2_common/hardware_ticks/include",
        "/src/rp2_common/pico_platform_sections/include",
        "/src/rp2_common/hardware_xip_cache/include",
        "/src/rp2_common/pico_aon_timer/include",
        "/src/rp2_common/pico_fix/rp2040_usb_device_enumeration/include",
        "/src/rp2_common/pico_sha256/include",
        "/src/rp2_common/pico_cyw43_arch/include",
        "/src/rp2_common/hardware_boot_lock/include",
        "/src/rp2_common/hardware_dcp/include",
        "/src/rp2_common/pico_double/include",
        "/src/rp2_common/cmsis/include",
        "/src/rp2_common/pico_unique_id/include",
        "/src/rp2_common/hardware_pwm/include",
        "/src/rp2_common/pico_platform_panic/include",
        "/src/rp2_common/hardware_vreg/include",
        "/src/rp2_common/hardware_dma/include",
        "/src/rp2_common/boot_bootrom_headers/include",
        "/src/rp2_common/hardware_sync_spin_lock/include",
        "/src/rp2_common/pico_platform_compiler/include",
        "/src/rp2_common/pico_i2c_slave/include",
        "/src/rp2_common/pico_printf/include",
        "/src/rp2_common/pico_int64_ops/include",
        "/src/rp2_common/pico_runtime_init/include",
        "/src/rp2_common/pico_stdio_uart/include",
        "/src/rp2_common/hardware_riscv/include",
        "/src/rp2_common/pico_atomic/include",
        "/src/rp2_common/pico_time_adapter/include",
        "/src/rp2_common/pico_mem_ops/include",
        "/src/rp2_common/hardware_hazard3/include",
        "/src/rp2_common/hardware_resets/include",
        "/src/rp2_common/pico_cyw43_driver/include",
        "/src/rp2_common/pico_clib_interface/include",
        "/src/rp2_common/pico_float/include",
        "/src/rp2_common/hardware_sha256/include",
        "/src/rp2_common/hardware_adc/include",
        "/src/rp2_common/hardware_watchdog/include",
        "/src/rp2_common/pico_rand/include",
        "/src/rp2_common/pico_runtime/include",
        "/src/rp2_common/hardware_spi/include",
        "/src/rp2_common/hardware_divider/include",
        "/src/rp2_common/tinyusb/include",
        "/src/rp2_common/pico_mbedtls/include",
        "/src/rp2_common/hardware_rtc/include",
        "/src/rp2_common/pico_stdio/include",
        "/src/rp2_common/hardware_xosc/include",
        "/src/rp2_common/pico_async_context/include",
        "/src/rp2_common/pico_flash/include",
        "/src/rp2_common/hardware_flash/include",
        "/src/rp2_common/pico_stdio_usb/include",
        "/src/rp2040/boot_stage2/include",
        "/src/rp2040/hardware_regs/include",
        "/src/rp2040/hardware_structs/include",
        "/src/rp2040/pico_platform/include",
    };

    for (pico_sdk_includes) |path| {
        const include_path = std.fs.path.join(b.allocator, &[_][]const u8{ pico_sdk_path, path }) catch {
            return;
        };
        lib.addIncludePath(.{ .cwd_relative = include_path });
    }

    // Platform Specific macros
    lib.root_module.addCMacro("PICO_RP2040", "1");
    lib.root_module.addCMacro("PICO_32BIT", "1");
    lib.root_module.addCMacro("PICO_ARM", "1");
    lib.root_module.addCMacro("PICO_CMSIS_DEVICE", "RP2040");
    lib.root_module.addCMacro("PICO_DEFAULT_FLASH_SIZE_BYTES", "\"2 * 1024 * 1024\"");

    // UART or USB
    lib.root_module.addCMacro(PicoStdlibDefine, "1");

    // Macros for Pico W
    lib.root_module.addCMacro("PICO_CYW43_ARCH_THREADSAFE_BACKGROUND", "1");
    const cyw43_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/cyw43-driver/src", .{pico_sdk_path});
    lib.addIncludePath(.{ .cwd_relative = cyw43_include });

    // required by cyw43
    const lwip_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/lwip/src/include", .{pico_sdk_path});
    lib.addIncludePath(.{ .cwd_relative = lwip_include });

    // options headers
    lib.addIncludePath(b.path("config/"));

    lib.addAssemblyFile(b.path("src/switch.s"));

    // lib.addIncludePath(b.path("include/"));

    const compiled = lib.getEmittedBin();
    const install_step = b.addInstallFile(compiled, "mlem.o");
    install_step.step.dependOn(&lib.step);

    if (std.fs.cwd().makeDir("build")) |_| {} else |err| {
        if (err != error.PathAlreadyExists) return err;
    }

    const uart_or_usb = if (StdioUsb) "-DSTDIO_USB=1" else "-DSTDIO_UART=1";
    const cmake_pico_sdk_path = b.fmt("-DPICO_SDK_PATH={s}", .{pico_sdk_path});

    var build_generator: []const u8 = undefined;

    const os = builtin.target.os.tag;
    if (os == .windows) {
        build_generator = "MinGW Makefiles";
    } else if (os == .macos or os == .linux) {
        build_generator = "Unix Makefiles";
    }

    const cmake_argv = [_][]const u8{
        "cmake",
        "-G",
        build_generator,
        "-B",
        "./build",
        "-S .",
        "-DPICO_BOARD=" ++ @tagName(Board),
        "-DPICO_PLATFORM=" ++ @tagName(Platform),
        cmake_pico_sdk_path,
        uart_or_usb,
    };

    const cmake_step = b.addSystemCommand(&cmake_argv);
    cmake_step.step.dependOn(&install_step.step);

    const make_argv = [_][]const u8{ "cmake", "--build", "./build", "--parallel" };
    const make_step = b.addSystemCommand(&make_argv);
    make_step.step.dependOn(&cmake_step.step);

    const uf2_create_step = b.addInstallFile(b.path("build/mlem.uf2"), "firmware.uf2");
    uf2_create_step.step.dependOn(&make_step.step);

    const uf2_step = b.step("uf2", "Create firmware.uf2");
    uf2_step.dependOn(&uf2_create_step.step);
    b.default_step = uf2_step;
}
