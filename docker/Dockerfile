FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG VERILATOR_VERSION=v5.034

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    bison \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    curl \
    flex \
    fpga-icestorm \
    git \
    iverilog \
    libfl-dev \
    lsb-release \
    make \
    nextpnr-ecp5 \
    nextpnr-ice40 \
    perl \
    pkg-config \
    python3 \
    python3-dev \
    python3-pip \
    sudo \
    tmux \
    vim \
    wget \
    yosys \
    zlib1g-dev \
    gcc-riscv64-unknown-elf \
    binutils-riscv64-unknown-elf \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/verilator-src /opt/verilator \
 && wget -qO- "https://github.com/verilator/verilator/archive/refs/tags/${VERILATOR_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 -C /tmp/verilator-src \
 && cd /tmp/verilator-src \
 && autoconf \
 && ./configure --prefix=/opt/verilator \
 && make -j"$(nproc)" \
 && make install \
 && rm -rf /tmp/verilator-src

ENV PATH="/opt/verilator/bin:${PATH}"

RUN python3 -m pip install --no-cache-dir --upgrade pip \
 && python3 -m pip install --no-cache-dir \
    cocotb \
    pyuvm \
    numpy \
    torch \
    onnx \
    matplotlib

RUN useradd --create-home --shell /bin/bash dev \
 && usermod -aG sudo dev \
 && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \
 && chmod 0440 /etc/sudoers.d/dev

WORKDIR /workspace
USER dev
