#!/usr/bin/env bash
# ==============================================================================
# Script: 02_fetch_toolchain.sh
# Purpose: Download or prepare cross-compiler toolchain (Clang & GCC)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source config if available
CONFIG_FILE="${ROOT_DIR}/config/config.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

TOOLCHAIN_TYPE="${TOOLCHAIN_TYPE:-proton-clang}"
AOSP_CLANG_VERSION="${AOSP_CLANG_VERSION:-r450784d}"
TOOLCHAIN_DIR="${ROOT_DIR}/toolchain"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "$TOOLCHAIN_DIR"

log_info "Chuẩn bị Toolchain: ${TOOLCHAIN_TYPE}..."

case "$TOOLCHAIN_TYPE" in
    proton-clang)
        TARGET_DIR="${TOOLCHAIN_DIR}/proton-clang"
        if [ -x "${TARGET_DIR}/bin/clang" ]; then
            log_ok "Proton Clang đã tồn tại tại ${TARGET_DIR}"
        else
            log_info "Đang tải Proton Clang (kdrag0n)..."
            rm -rf "$TARGET_DIR"
            git clone --depth=1 https://github.com/kdrag0n/proton-clang.git "$TARGET_DIR"
            log_ok "Đã tải xong Proton Clang."
        fi
        CLANG_BIN="${TARGET_DIR}/bin/clang"
        ;;

    aosp-clang)
        TARGET_DIR="${TOOLCHAIN_DIR}/clang-${AOSP_CLANG_VERSION}"
        if [ -x "${TARGET_DIR}/bin/clang" ]; then
            log_ok "AOSP Clang ${AOSP_CLANG_VERSION} đã tồn tại tại ${TARGET_DIR}"
        else
            log_info "Đang tải AOSP Clang ${AOSP_CLANG_VERSION} từ Google Git..."
            mkdir -p "$TARGET_DIR"
            CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-${AOSP_CLANG_VERSION}.tar.gz"
            if ! curl -sSL -o "${TOOLCHAIN_DIR}/clang.tar.gz" "$CLANG_URL"; then
                log_warn "Không tải được từ Google master branch, thử mirror crDroid/LineageOS..."
                git clone --depth=1 "https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-${AOSP_CLANG_VERSION}.git" "$TARGET_DIR" || {
                    log_error "Lỗi: Không tìm thấy AOSP Clang phiên bản ${AOSP_CLANG_VERSION}!"
                    exit 1
                }
            else
                tar -xzf "${TOOLCHAIN_DIR}/clang.tar.gz" -C "$TARGET_DIR"
                rm -f "${TOOLCHAIN_DIR}/clang.tar.gz"
            fi
            log_ok "Đã chuẩn bị xong AOSP Clang ${AOSP_CLANG_VERSION}."
        fi

        # Setup AOSP GCC prebuilts if system cross-compiler is not preferred
        GCC64_DIR="${TOOLCHAIN_DIR}/aarch64-linux-android-4.9"
        if [ ! -d "$GCC64_DIR" ]; then
            log_info "Đang tải prebuilt aarch64-linux-android-4.9..."
            git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 "$GCC64_DIR" || log_warn "Bỏ qua AOSP GCC64, sẽ dùng system gcc nếu cần."
        fi

        GCC32_DIR="${TOOLCHAIN_DIR}/arm-linux-androideabi-4.9"
        if [ ! -d "$GCC32_DIR" ]; then
            log_info "Đang tải prebuilt arm-linux-androideabi-4.9..."
            git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 "$GCC32_DIR" || log_warn "Bỏ qua AOSP GCC32, sẽ dùng system gcc nếu cần."
        fi

        CLANG_BIN="${TARGET_DIR}/bin/clang"
        ;;

    custom)
        if [ -z "${CUSTOM_TOOLCHAIN_PATH:-}" ] || [ ! -x "${CUSTOM_TOOLCHAIN_PATH}/bin/clang" ]; then
            log_error "Vui lòng đặt CUSTOM_TOOLCHAIN_PATH trỏ tới thư mục chứa bin/clang!"
            exit 1
        fi
        CLANG_BIN="${CUSTOM_TOOLCHAIN_PATH}/bin/clang"
        ;;

    *)
        log_error "Loại Toolchain không hỗ trợ: ${TOOLCHAIN_TYPE}"
        exit 1
        ;;
esac

log_ok "Compiler Version:"
"$CLANG_BIN" --version | head -n 2
