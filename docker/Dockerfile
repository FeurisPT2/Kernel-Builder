FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install required dependencies
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    libncurses5-dev \
    libncurses-dev \
    ccache \
    curl \
    git \
    python3 \
    python3-pip \
    zip \
    unzip \
    tar \
    xz-utils \
    zstd \
    lz4 \
    patch \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi \
    binutils-aarch64-linux-gnu \
    binutils-arm-linux-gnueabi \
    device-tree-compiler \
    file \
    rsync \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["/bin/bash", "./build.sh", "--skip-env"]
