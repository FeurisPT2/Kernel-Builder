#!/usr/bin/env bash
# ==============================================================================
# Script: 03_fetch_source.sh
# Purpose: Clone or update Android Kernel source tree
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE="${ROOT_DIR}/config/config.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

KERNEL_SOURCE="${KERNEL_SOURCE:-}"
KERNEL_BRANCH="${KERNEL_BRANCH:-}"
SOURCE_DIR="${ROOT_DIR}/source/kernel"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [ -z "$KERNEL_SOURCE" ]; then
    log_error "Chưa thiết lập biến KERNEL_SOURCE trong config/config.env!"
    exit 1
fi

mkdir -p "${ROOT_DIR}/source"

if [ -d "${SOURCE_DIR}/.git" ]; then
    log_info "Thư mục source kernel đã tồn tại, kiểm tra và cập nhật..."
    cd "$SOURCE_DIR"
    git fetch --depth=1 origin "${KERNEL_BRANCH:-HEAD}" || true
    if [ -n "$KERNEL_BRANCH" ]; then
        git checkout "$KERNEL_BRANCH" || true
    fi
else
    log_info "Đang clone kernel source từ: $KERNEL_SOURCE..."
    CLONE_ARGS=(--depth=1)
    if [ -n "$KERNEL_BRANCH" ]; then
        CLONE_ARGS+=(--branch "$KERNEL_BRANCH")
    fi

    # Clone with depth=1 for fast cloning
    git clone "${CLONE_ARGS[@]}" "$KERNEL_SOURCE" "$SOURCE_DIR"
    log_ok "Clone kernel source thành công!"
fi

cd "$SOURCE_DIR"

# Detect whether this is standard kernel root or common/
KERNEL_ROOT="$SOURCE_DIR"
if [ -f "$SOURCE_DIR/common/Makefile" ]; then
    KERNEL_ROOT="$SOURCE_DIR/common"
fi

if [ ! -f "$KERNEL_ROOT/Makefile" ]; then
    log_error "Không tìm thấy Makefile tại $KERNEL_ROOT! Vui lòng kiểm tra lại repository."
    exit 1
fi

# Fix common Xiaomi OSS missing headers bug (e.g. drivers/misc/hwid/hwid.h)
if [ ! -f "$KERNEL_ROOT/drivers/misc/hwid/hwid.h" ]; then
    log_info "Tạo stub cho drivers/misc/hwid/hwid.h (file Xiaomi bỏ quên trong bản OSS)..."
    mkdir -p "$KERNEL_ROOT/drivers/misc/hwid"
    cat << 'EOF' > "$KERNEL_ROOT/drivers/misc/hwid/hwid.h"
/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_HWID_H
#define _LINUX_HWID_H
static inline int get_hwid_val(void) { return 0; }
#endif
EOF
fi

# Also remove hardcoded broken include if present in aw882xx.c
if [ -f "$KERNEL_ROOT/sound/soc/codecs/aw882xx/aw882xx.c" ]; then
    sed -i 's|#include "../../../drivers/misc/hwid/hwid.h"|/* #include hwid.h */|g' "$KERNEL_ROOT/sound/soc/codecs/aw882xx/aw882xx.c" || true
fi

# Detect Kernel Version
VERSION=$(grep -E '^VERSION = ' "$KERNEL_ROOT/Makefile" | awk '{print $3}')
PATCHLEVEL=$(grep -E '^PATCHLEVEL = ' "$KERNEL_ROOT/Makefile" | awk '{print $3}')
SUBLEVEL=$(grep -E '^SUBLEVEL = ' "$KERNEL_ROOT/Makefile" | awk '{print $3}' || echo "0")

FULL_KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"
log_ok "Đã nhận diện phiên bản Kernel: ${FULL_KERNEL_VERSION} (Nhánh ${VERSION}.${PATCHLEVEL})"

# Save detected info to temporary build state
mkdir -p "${ROOT_DIR}/work"
cat <<EOF > "${ROOT_DIR}/work/kernel_info.env"
KERNEL_ROOT_DIR="${KERNEL_ROOT}"
KERNEL_BASE_VERSION="${VERSION}.${PATCHLEVEL}"
KERNEL_FULL_VERSION="${FULL_KERNEL_VERSION}"
EOF

log_ok "Kernel Source đã sẵn sàng tại: $KERNEL_ROOT"
