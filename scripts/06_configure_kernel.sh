#!/usr/bin/env bash
# ==============================================================================
# Script: 06_configure_kernel.sh
# Purpose: Configure kernel with defconfig and merge KSU/SUSFS options
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

KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-defconfig}"
ARCH="${ARCH:-arm64}"
SUBARCH="${SUBARCH:-arm64}"
ENABLE_RESUKISU="${ENABLE_RESUKISU:-true}"
ENABLE_SUSFS="${ENABLE_SUSFS:-true}"

OUT_DIR="${ROOT_DIR}/out"
mkdir -p "$OUT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

cd "$KERNEL_ROOT_DIR"

log_info "Tạo cấu hình ban đầu từ defconfig: ${KERNEL_DEFCONFIG}..."

# Run base defconfig
make O="$OUT_DIR" ARCH="$ARCH" SUBARCH="$SUBARCH" "$KERNEL_DEFCONFIG"

# Function to enable config option via scripts/config or direct append
# Usage: set_kconfig KEY value  (KEY without CONFIG_ prefix)
set_kconfig() {
    local opt="$1"
    local val="$2"
    local full_opt="CONFIG_${opt}"
    if [ -x "${KERNEL_ROOT_DIR}/scripts/config" ]; then
        if [ "$val" = "y" ]; then
            "${KERNEL_ROOT_DIR}/scripts/config" --file "$OUT_DIR/.config" -e "$full_opt"
        elif [ "$val" = "n" ]; then
            "${KERNEL_ROOT_DIR}/scripts/config" --file "$OUT_DIR/.config" -d "$full_opt"
        elif [ "$val" = "m" ]; then
            "${KERNEL_ROOT_DIR}/scripts/config" --file "$OUT_DIR/.config" -m "$full_opt"
        elif [[ "$val" =~ ^[0-9]+$ ]]; then
            "${KERNEL_ROOT_DIR}/scripts/config" --file "$OUT_DIR/.config" --set-val "$full_opt" "$val"
        else
            "${KERNEL_ROOT_DIR}/scripts/config" --file "$OUT_DIR/.config" --set-str "$full_opt" "$val"
        fi
    else
        # Fallback: remove existing entry (handles both =y and # ...is not set) then append
        sed -i "/^${full_opt}[= ]/d" "$OUT_DIR/.config"
        sed -i "/^# ${full_opt} /d" "$OUT_DIR/.config"
        if [ "$val" = "y" ] || [ "$val" = "m" ] || [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "${full_opt}=${val}" >> "$OUT_DIR/.config"
        elif [ "$val" = "n" ]; then
            echo "# ${full_opt} is not set" >> "$OUT_DIR/.config"
        else
            echo "${full_opt}=\"${val}\"" >> "$OUT_DIR/.config"
        fi
    fi
}

# Merge ReSukiSU configs
if [ "$ENABLE_RESUKISU" = "true" ]; then
    log_info "Bật các cờ cấu hình ReSukiSU..."
    set_kconfig "KSU" "y"
    set_kconfig "KSU_DEBUG" "n"
    set_kconfig "KSU_MULTI_MANAGER_SUPPORT" "y"
    set_kconfig "KALLSYMS" "y"
    set_kconfig "KALLSYMS_ALL" "y"
    set_kconfig "OVERLAY_FS" "y"
fi

# Merge SUSFS configs
if [ "$ENABLE_SUSFS" = "true" ]; then
    log_info "Bật các cờ cấu hình SUSFS..."
    set_kconfig "KSU_SUSFS" "y"
    set_kconfig "KSU_SUSFS_SUS_PATH" "y"
    set_kconfig "KSU_SUSFS_SUS_MOUNT" "y"
    set_kconfig "KSU_SUSFS_SUS_KSTAT" "y"
    set_kconfig "KSU_SUSFS_SPOOF_UNAME" "y"
    set_kconfig "KSU_SUSFS_ENABLE_LOG" "y"
    set_kconfig "KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS" "y"
    set_kconfig "KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG" "y"
    set_kconfig "KSU_SUSFS_OPEN_REDIRECT" "y"
    set_kconfig "KSU_SUSFS_SUS_MAP" "y"
fi

# Disable stack frame warning & warnings-as-errors to prevent compile aborts on inlined functions (e.g. io_uring)
log_info "Tắt giới hạn FRAME_WARN và WERROR để tránh lỗi compiler warnings..."
set_kconfig "FRAME_WARN" "0"
set_kconfig "WERROR" "n"

# Remove -dirty flag from kernel release string to prevent detection by banking/integrity apps
if [ -f "${KERNEL_ROOT_DIR}/scripts/setlocalversion" ]; then
    log_info "Loại bỏ hậu tố -dirty trong scripts/setlocalversion..."
    sed -i "s/printf '%s' -dirty/printf '%s' ''/g" "${KERNEL_ROOT_DIR}/scripts/setlocalversion" || true
    sed -i 's/echo "\$res-dirty"/echo "\$res"/g' "${KERNEL_ROOT_DIR}/scripts/setlocalversion" || true
fi

# Resolve dependencies with olddefconfig
log_info "Cập nhật và kiểm tra cấu hình bằng olddefconfig..."
make O="$OUT_DIR" ARCH="$ARCH" SUBARCH="$SUBARCH" olddefconfig

# Verification
log_info "Kiểm tra các cờ đã được bật:"
grep -E "CONFIG_KSU(=| )|CONFIG_KSU_SUSFS(=| )" "$OUT_DIR/.config" || true

log_ok "Cấu hình kernel đã sẵn sàng tại: $OUT_DIR/.config"
