#!/usr/bin/env bash
# ==============================================================================
# Script: 08_package_kernel.sh
# Purpose: Package compiled kernel into flashable AnyKernel3 ZIP
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
fi

DEVICE_NAME="${DEVICE_NAME:-device}"
DEVICE_MODEL="${DEVICE_MODEL:-Android}"
ENABLE_ANYKERNEL3="${ENABLE_ANYKERNEL3:-true}"
ANYKERNEL3_REPO="${ANYKERNEL3_REPO:-https://github.com/osm0sis/AnyKernel3.git}"
ANYKERNEL3_BRANCH="${ANYKERNEL3_BRANCH:-master}"

OUTPUT_DIR="${ROOT_DIR}/output"
mkdir -p "$OUTPUT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [ "$ENABLE_ANYKERNEL3" != "true" ]; then
    log_info "ENABLE_ANYKERNEL3=false -> Chỉ copy raw image ra thư mục output."
    if [ -n "${COMPILED_IMAGE_PATH:-}" ] && [ -f "$COMPILED_IMAGE_PATH" ]; then
        cp -vf "$COMPILED_IMAGE_PATH" "$OUTPUT_DIR/"
        log_ok "Đã lưu raw kernel image tại: $OUTPUT_DIR/$(basename "$COMPILED_IMAGE_PATH")"
    fi
    exit 0
fi

if [ -z "${COMPILED_IMAGE_PATH:-}" ] || [ ! -f "$COMPILED_IMAGE_PATH" ]; then
    log_error "Lỗi: Không tìm thấy COMPILED_IMAGE_PATH để đóng gói AnyKernel3!"
    exit 1
fi

log_info "Bắt đầu đóng gói kernel vào AnyKernel3..."

AK3_DIR="${ROOT_DIR}/work/AnyKernel3"
rm -rf "$AK3_DIR"
git clone --depth=1 --branch "$ANYKERNEL3_BRANCH" "$ANYKERNEL3_REPO" "$AK3_DIR"

# Copy kernel image
IMAGE_BASENAME="$(basename "$COMPILED_IMAGE_PATH")"
cp -vf "$COMPILED_IMAGE_PATH" "${AK3_DIR}/${IMAGE_BASENAME}"
log_ok "Đã copy ${IMAGE_BASENAME} vào AnyKernel3."

# If image is Image.gz-dtb or Image.gz or Image, check for extra dtb / dtbo
if [ -n "${BOOT_DIR:-}" ] && [ -d "$BOOT_DIR" ]; then
    if [ -f "${BOOT_DIR}/dtb.img" ]; then
        cp -vf "${BOOT_DIR}/dtb.img" "${AK3_DIR}/dtb"
        log_ok "Đã copy dtb.img vào AnyKernel3."
    elif [ -f "${BOOT_DIR}/dtb" ]; then
        cp -vf "${BOOT_DIR}/dtb" "${AK3_DIR}/dtb"
        log_ok "Đã copy dtb vào AnyKernel3."
    fi

    if [ -f "${BOOT_DIR}/dtbo.img" ]; then
        cp -vf "${BOOT_DIR}/dtbo.img" "${AK3_DIR}/dtbo.img"
        log_ok "Đã copy dtbo.img vào AnyKernel3."
    fi
fi

cd "$AK3_DIR"

# Customize anykernel.sh with device details if anykernel.sh exists
if [ -f "anykernel.sh" ]; then
    sed -i "s/device.name1=.*/device.name1=${DEVICE_NAME}/" anykernel.sh || true
    # Remove git and unnecessary files before zipping
    rm -rf .git .github README.md
fi

# Build ZIP filename
BUILD_DATE=$(date +%Y%m%d_%H%M%S)
ZIP_NAME="${DEVICE_NAME}_ReSukiSU_SUSFS_${BUILD_DATE}.zip"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

log_info "Tạo file flashable ZIP: ${ZIP_NAME}..."
zip -r9 "$ZIP_PATH" ./* -x .git README.md ./*placeholder

# Generate SHA256 checksum
cd "$OUTPUT_DIR"
sha256sum "$ZIP_NAME" > "${ZIP_NAME}.sha256"

log_ok "=========================================================="
log_ok " ĐÓNG GÓI HOÀN TẤT THÀNH CÔNG!"
log_ok " File ZIP flash qua Recovery: ${ZIP_PATH}"
log_ok " Checksum SHA256: $(cat "${ZIP_NAME}.sha256")"
log_ok " Dung lượng file: $(ls -lh "$ZIP_PATH" | awk '{print $5}')"
log_ok "=========================================================="
