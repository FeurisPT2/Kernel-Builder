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
            # Map AOSP Clang version to correct Google Git branch
            case "$AOSP_CLANG_VERSION" in
                r416183*) CLANG_BRANCH="master-kernel-build-2021" ;;
                r450784*) CLANG_BRANCH="master-kernel-build-2022" ;;
                r487747*|r498229*) CLANG_BRANCH="main-kernel-build-2023" ;;
                r510928*|r522817*) CLANG_BRANCH="main-kernel-build-2024" ;;
                r536225*|r547379*) CLANG_BRANCH="main-kernel-2025" ;;
                r584948*) CLANG_BRANCH="main-kernel-2026" ;;
                r596125*) CLANG_BRANCH="main-kernel" ;;
                *) CLANG_BRANCH="master-kernel-build-2022" ;;
            esac

            log_info "Đang tải AOSP Clang ${AOSP_CLANG_VERSION} từ Google Git (nhánh ${CLANG_BRANCH})..."
            mkdir -p "$TARGET_DIR"
            CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${CLANG_BRANCH}/clang-${AOSP_CLANG_VERSION}.tar.gz"

            DOWNLOAD_OK=false
            if curl -sSL --fail -o "${TOOLCHAIN_DIR}/clang.tar.gz" "$CLANG_URL"; then
                # Ensure downloaded archive is not an empty/keep archive (> 10MB)
                ARCHIVE_SIZE=$(wc -c < "${TOOLCHAIN_DIR}/clang.tar.gz" || echo "0")
                if [ "$ARCHIVE_SIZE" -gt 10000000 ]; then
                    log_info "Giải nén AOSP Clang (${ARCHIVE_SIZE} bytes)..."
                    tar -xzf "${TOOLCHAIN_DIR}/clang.tar.gz" -C "$TARGET_DIR"
                    rm -f "${TOOLCHAIN_DIR}/clang.tar.gz"
                    DOWNLOAD_OK=true
                else
                    log_warn "Archive tải về từ Google Git quá nhỏ (${ARCHIVE_SIZE} bytes - có thể chỉ là file .keep placeholder)."
                    rm -f "${TOOLCHAIN_DIR}/clang.tar.gz"
                fi
            fi

            if [ "$DOWNLOAD_OK" = "false" ]; then
                log_warn "Thử tải AOSP Clang từ mirror GitHub..."
                git clone --depth=1 "https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-${AOSP_CLANG_VERSION}.git" "$TARGET_DIR" || {
                    log_error "Lỗi: Không tìm thấy AOSP Clang phiên bản ${AOSP_CLANG_VERSION}!"
                    exit 1
                }
            fi
            log_ok "Đã chuẩn bị xong AOSP Clang ${AOSP_CLANG_VERSION}."
        fi

        # Setup GCC only if LLVM=0 and system cross compiler is missing
        if [ "${LLVM:-1}" = "0" ] && ! command -v aarch64-linux-gnu-gcc &>/dev/null; then
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
