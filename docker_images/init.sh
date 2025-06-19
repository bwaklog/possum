#!/bin/bash

cd app

export PATH="/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi/bin/":$PATH
export ARM_NONE_EABI_PATH="/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi/arm-none-eabi/include"
export PATH="/zig-aarch64-linux-0.14.1/":$PATH
export PICO_SDK_PATH="/app/pico-sdk"

zig build
