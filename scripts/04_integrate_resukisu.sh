#!/usr/bin/env bash
# ==============================================================================
# Script: 04_integrate_resukisu.sh
# Purpose: Integrate ReSukiSU root driver into kernel source tree
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

ENABLE_RESUKISU="${ENABLE_RESUKISU:-true}"
RESUKISU_REPO="${RESUKISU_REPO:-https://github.com/ReSukiSU/ReSukiSU.git}"
RESUKISU_BRANCH="${RESUKISU_BRANCH:-main}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [ "$ENABLE_RESUKISU" != "true" ]; then
    log_info "Tùy chọn ENABLE_RESUKISU=false -> Bỏ qua tích hợp ReSukiSU."
    exit 0
fi

log_info "Bắt đầu tích hợp ReSukiSU vào Kernel tại: ${KERNEL_ROOT_DIR}..."

cd "$KERNEL_ROOT_DIR"

# Determine drivers directory
if [ -d "${KERNEL_ROOT_DIR}/drivers" ]; then
    DRIVERS_DIR="${KERNEL_ROOT_DIR}/drivers"
elif [ -d "${KERNEL_ROOT_DIR}/common/drivers" ]; then
    DRIVERS_DIR="${KERNEL_ROOT_DIR}/common/drivers"
else
    log_error "Không tìm thấy thư mục drivers/ trong source kernel!"
    exit 1
fi

DRIVER_MAKEFILE="${DRIVERS_DIR}/Makefile"
DRIVER_KCONFIG="${DRIVERS_DIR}/Kconfig"

# Clone or update ReSukiSU into KernelSU
KSU_DIR="${KERNEL_ROOT_DIR}/KernelSU"
if [ -d "$KSU_DIR" ]; then
    log_info "Thư mục KernelSU đã tồn tại, cập nhật ReSukiSU..."
    cd "$KSU_DIR"
    git fetch --depth=1 origin "$RESUKISU_BRANCH" || true
    git checkout "$RESUKISU_BRANCH" || git checkout -b "$RESUKISU_BRANCH" "FETCH_HEAD" || true
    git reset --hard FETCH_HEAD || true
else
    log_info "Đang clone ReSukiSU (${RESUKISU_BRANCH}) từ ${RESUKISU_REPO}..."
    git clone --depth=1 --branch "$RESUKISU_BRANCH" "$RESUKISU_REPO" "$KSU_DIR"
fi

# Create symlink drivers/kernelsu -> ../KernelSU/kernel
cd "$DRIVERS_DIR"
REL_PATH="$(realpath --relative-to="$DRIVERS_DIR" "$KSU_DIR/kernel")"
rm -f "kernelsu"
ln -sf "$REL_PATH" "kernelsu"
log_ok "Đã tạo symlink drivers/kernelsu -> ${REL_PATH}"

# Inject into drivers/Makefile
if grep -q "kernelsu" "$DRIVER_MAKEFILE"; then
    log_ok "Makefile đã có định nghĩa kernelsu."
else
    echo -e "\nobj-\$(CONFIG_KSU) += kernelsu/" >> "$DRIVER_MAKEFILE"
    log_ok "Đã thêm 'obj-\$(CONFIG_KSU) += kernelsu/' vào drivers/Makefile"
fi

# Inject into drivers/Kconfig
if grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG"; then
    log_ok "Kconfig đã có liên kết drivers/kernelsu/Kconfig."
else
    if grep -q "endmenu" "$DRIVER_KCONFIG"; then
        # Insert before the LAST endmenu only (not every endmenu)
        python3 -c "
import sys
lines = open('$DRIVER_KCONFIG').readlines()
# Find last occurrence of endmenu
last_idx = max(i for i, l in enumerate(lines) if 'endmenu' in l)
lines.insert(last_idx, 'source \"drivers/kernelsu/Kconfig\"\n')
open('$DRIVER_KCONFIG', 'w').writelines(lines)
"
    else
        printf '\nsource "drivers/kernelsu/Kconfig"\n' >> "$DRIVER_KCONFIG"
    fi
    log_ok "Đã thêm source \"drivers/kernelsu/Kconfig\" vào drivers/Kconfig"
fi

# Verify integration
if [ -f "$DRIVERS_DIR/kernelsu/Kconfig" ]; then
    log_ok "Tích hợp ReSukiSU thành công! (Phiên bản hỗ trợ KSU_SUSFS inline hook sẵn có)"
else
    log_error "Lỗi: Không tìm thấy $DRIVERS_DIR/kernelsu/Kconfig sau khi tạo symlink!"
    exit 1
fi
