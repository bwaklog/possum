FROM ubuntu:latest

RUN apt update
RUN apt upgrade -y
RUN apt install -y cmake git make python3 curl bash xz-utils build-essential

RUN curl -LO https://ziglang.org/download/0.14.1/zig-aarch64-linux-0.14.1.tar.xz
RUN curl -LO https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi.tar.xz

RUN tar -xJf zig-aarch64-linux-0.14.1.tar.xz
RUN tar -xJf arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi.tar.xz

RUN echo 'export PATH="/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi/bin/":$PATH' >> ~/.bashrc
RUN echo 'export ARM_NONE_EABI_PATH="/arm-gnu-toolchain-14.2.rel1-aarch64-arm-none-eabi/arm-none-eabi/include"' >> ~/.bashrc
RUN echo 'export PATH="/zig-aarch64-linux-0.14.1/":$PATH' >> ~/.bashrc
RUN echo 'export PICO_SDK_PATH="/app/pico-sdk"' >> ~/.bashrc
RUN mkdir /app

COPY ./docker_images/init.sh  .
RUN chmod +x init.sh

CMD ["./init.sh"]
