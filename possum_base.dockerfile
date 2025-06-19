FROM ubuntu:latest

RUN apt-get update
RUN apt-get upgrade -y
RUN apt install -y cmake git make python3 xz-utils curl

RUN curl -LO https://ziglang.org/download/0.14.1/zig-aarch64-linux-0.14.1.tar.xz
RUN xz -d zig-aarch64-linux-0.14.1.tar.xz
RUN tar -xvf zig-aarch64-linux-0.14.1.tar
RUN echo 'export PATH="/zig-aarch64-linux-0.14.1/":$PATH' >> ~/.bashrc

RUN curl -LO https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi.tar.xz
RUN xz -d arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi.tar.xz
RUN tar -xvf arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi.tar
RUN echo 'export PATH="/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi/bin/":$PATH' >> ~/.bashrc
RUN echo 'export ARM_NONE_EABI_PATH="/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi/arm-none-eabi/include"' >> ~/.bashrc

RUN echo 'export PICO_SDK_PATH="/app/pico-sdk"' >> ~/.bashrc
