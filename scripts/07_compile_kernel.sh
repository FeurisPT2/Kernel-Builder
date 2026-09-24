#!/usr/bin/env bash
# ==============================================================================
# Script: 07_compile_kernel.sh
# Purpose: Build the Android Kernel using configured Clang/GCC toolchain
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE="${ROOT_DIR}/config/config.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

INFO_FILE="${ROOT_DIR}/work/kernel_info.env"
if [ -f "$INFO_FILE" ]; then
    # shellcheck source=/dev/null
    source "$INFO_FILE"
else
    KERNEL_ROOT_DIR="${ROOT_DIR}/source/kernel"
fi

ARCH="${ARCH:-arm64}"
SUBARCH="${SUBARCH:-arm64}"
TOOLCHAIN_TYPE="${TOOLCHAIN_TYPE:-proton-clang}"
AOSP_CLANG_VERSION="${AOSP_CLANG_VERSION:-r450784d}"
LLVM="${LLVM:-1}"
OUT_DIR="${ROOT_DIR}/out"
KERNEL_IMAGE_NAME="${KERNEL_IMAGE_NAME:-Image}"
BUILD_DTBO="${BUILD_DTBO:-false}"
EXTRA_MAKE_FLAGS="${EXTRA_MAKE_FLAGS:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Setup toolchain PATH
case "$TOOLCHAIN_TYPE" in
    proton-clang)
        TC_BIN="${ROOT_DIR}/toolchain/proton-clang/bin"
        export PATH="${TC_BIN}:${PATH}"
        CROSS_COMPILE="aarch64-linux-gnu-"
        CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
        ;;
    aosp-clang)
        TC_BIN="${ROOT_DIR}/toolchain/clang-${AOSP_CLANG_VERSION}/bin"
        GCC64_BIN="${ROOT_DIR}/toolchain/aarch64-linux-android-4.9/bin"
        GCC32_BIN="${ROOT_DIR}/toolchain/arm-linux-androideabi-4.9/bin"
        export PATH="${TC_BIN}:${GCC64_BIN}:${GCC32_BIN}:${PATH}"
        CROSS_COMPILE="aarch64-linux-android-"
        CROSS_COMPILE_ARM32="arm-linux-androideabi-"
        # If AOSP gcc not present, use system cross compilers
        if ! command -v "${CROSS_COMPILE}gcc" &>/dev/null; then
            CROSS_COMPILE="aarch64-linux-gnu-"
            CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
        fi
        ;;
    custom)
        if [ -n "${CUSTOM_TOOLCHAIN_PATH:-}" ]; then
            export PATH="${CUSTOM_TOOLCHAIN_PATH}/bin:${PATH}"
        fi
        CROSS_COMPILE="aarch64-linux-gnu-"
        CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
        ;;
esac

# Check compiler
if ! command -v clang &>/dev/null; then
    log_error "Lỗi: Không tìm thấy clang trong PATH!"
    exit 1
fi

log_info "Thông tin Compiler:"
clang --version | head -n 1

# Setup MAKE arguments
MAKE_ARGS=(
    O="$OUT_DIR"
    ARCH="$ARCH"
    SUBARCH="$SUBARCH"
    CC="clang"
)

if [ "$LLVM" = "1" ]; then
    MAKE_ARGS+=(
        LLVM=1
        LLVM_IAS=1
    )
else
    MAKE_ARGS+=(
        CROSS_COMPILE="$CROSS_COMPILE"
        CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32"
        CLANG_TRIPLE="aarch64-linux-gnu-"
    )
fi

# Append extra make flags if any
if [ -n "$EXTRA_MAKE_FLAGS" ]; then
    # shellcheck disable=SC2206
    MAKE_ARGS+=($EXTRA_MAKE_FLAGS)
fi

# Enable ccache if available
if command -v ccache &>/dev/null; then
    export USE_CCACHE=1
    export CCACHE_DIR="${ROOT_DIR}/ccache"
    mkdir -p "$CCACHE_DIR"
    # Correct approach: let ccache wrap clang via CC_WRAPPER, not CC= "ccache clang"
    export CC_WRAPPER="ccache"
    log_info "Đã kích hoạt ccache (CC_WRAPPER=ccache)."
fi

NPROC=$(nproc)
log_info "Bắt đầu biên dịch với ${NPROC} luồng CPU..."
START_TIME=$(date +%s)

cd "$KERNEL_ROOT_DIR"

# Build dtbo if requested (append as extra target)
if [ "${BUILD_DTBO:-false}" = "true" ]; then
    make -j"$NPROC" "${MAKE_ARGS[@]}" dtbo.img
else
    make -j"$NPROC" "${MAKE_ARGS[@]}"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log_ok "Biên dịch hoàn tất trong ${MINUTES} phút ${SECONDS} giây!"

# Locate generated kernel images
BOOT_DIR="${OUT_DIR}/arch/${ARCH}/boot"
FOUND_IMAGE=""

if [ -f "${BOOT_DIR}/${KERNEL_IMAGE_NAME}" ]; then
    FOUND_IMAGE="${BOOT_DIR}/${KERNEL_IMAGE_NAME}"
elif [ -f "${BOOT_DIR}/Image.gz-dtb" ]; then
    FOUND_IMAGE="${BOOT_DIR}/Image.gz-dtb"
elif [ -f "${BOOT_DIR}/Image.gz" ]; then
    FOUND_IMAGE="${BOOT_DIR}/Image.gz"
elif [ -f "${BOOT_DIR}/Image" ]; then
    FOUND_IMAGE="${BOOT_DIR}/Image"
fi

if [ -z "$FOUND_IMAGE" ] || [ ! -f "$FOUND_IMAGE" ]; then
    log_error "Lỗi: Không tìm thấy kernel image được tạo trong ${BOOT_DIR}!"
    ls -la "$BOOT_DIR" || true
    exit 1
fi

log_ok "Kernel Image đã được tạo thành công:"
ls -lh "$FOUND_IMAGE"

# Save image path for packager
cat <<EOF >> "${ROOT_DIR}/work/kernel_info.env"
COMPILED_IMAGE_PATH="${FOUND_IMAGE}"
BOOT_DIR="${BOOT_DIR}"
EOF
