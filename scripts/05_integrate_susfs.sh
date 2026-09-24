#!/usr/bin/env bash
# ==============================================================================
# Script: 05_integrate_susfs.sh
# Purpose: Integrate SUSFS (susfs4ksu) kernel patches & headers into kernel tree
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
    KERNEL_BASE_VERSION="5.10"
fi

ENABLE_SUSFS="${ENABLE_SUSFS:-true}"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-auto}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [ "$ENABLE_SUSFS" != "true" ]; then
    log_info "Tùy chọn ENABLE_SUSFS=false -> Bỏ qua tích hợp SUSFS."
    exit 0
fi

log_info "Bắt đầu tích hợp SUSFS (susfs4ksu) cho Kernel ${KERNEL_BASE_VERSION}..."

# Auto-detect matching SUSFS branch if set to auto
if [ "$SUSFS_BRANCH" = "auto" ]; then
    case "$KERNEL_BASE_VERSION" in
        4.9)
            TARGET_SUSFS_BRANCH="kernel-4.9"
            ;;
        4.14)
            TARGET_SUSFS_BRANCH="kernel-4.14"
            ;;
        4.19)
            TARGET_SUSFS_BRANCH="kernel-4.19"
            ;;
        5.4)
            TARGET_SUSFS_BRANCH="kernel-5.4"
            ;;
        5.10)
            TARGET_SUSFS_BRANCH="gki-android12-5.10"
            ;;
        5.15)
            # gki-android13-5.15 uses VMA_PAD_START which doesn't exist in OEM 5.15 kernels
            # Use the -dev branch which avoids that macro
            TARGET_SUSFS_BRANCH="gki-android13-5.15-dev"
            ;;
        6.1)
            TARGET_SUSFS_BRANCH="gki-android14-6.1"
            ;;
        6.6)
            TARGET_SUSFS_BRANCH="gki-android15-6.6"
            ;;
        6.12)
            TARGET_SUSFS_BRANCH="gki-android16-6.12"
            ;;
        *)
            log_warn "Không tìm thấy nhánh SUSFS phù hợp trực tiếp cho kernel ${KERNEL_BASE_VERSION}, mặc định dùng gki-android12-5.10"
            TARGET_SUSFS_BRANCH="gki-android12-5.10"
            ;;
    esac
else
    TARGET_SUSFS_BRANCH="$SUSFS_BRANCH"
fi

log_info "Sử dụng nhánh SUSFS: ${TARGET_SUSFS_BRANCH} từ ${SUSFS_REPO}"

SUSFS_WORK_DIR="${ROOT_DIR}/work/susfs4ksu"
rm -rf "$SUSFS_WORK_DIR"
mkdir -p "$SUSFS_WORK_DIR"

log_info "Đang clone SUSFS (${TARGET_SUSFS_BRANCH})..."
if ! git clone --depth=1 --branch "$TARGET_SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_WORK_DIR"; then
    log_error "Không thể clone nhánh '${TARGET_SUSFS_BRANCH}' từ ${SUSFS_REPO}!"
    exit 1
fi

PATCHES_DIR="${SUSFS_WORK_DIR}/kernel_patches"

if [ ! -d "$PATCHES_DIR" ]; then
    log_error "Không tìm thấy thư mục kernel_patches/ trong SUSFS repo! Có thể nhánh '${TARGET_SUSFS_BRANCH}' không phù hợp."
    exit 1
fi

# 1. Copy fs files
log_info "Copying SUSFS fs files..."
mkdir -p "${KERNEL_ROOT_DIR}/fs"
if [ -d "${PATCHES_DIR}/fs" ] && [ -n "$(ls -A "${PATCHES_DIR}/fs/" 2>/dev/null)" ]; then
    cp -rvf "${PATCHES_DIR}/fs/"* "${KERNEL_ROOT_DIR}/fs/"
else
    log_warn "Không có file nào trong ${PATCHES_DIR}/fs/ để copy."
fi

# 2. Copy include/linux headers
log_info "Copying SUSFS headers..."
mkdir -p "${KERNEL_ROOT_DIR}/include/linux"
if [ -d "${PATCHES_DIR}/include/linux" ] && [ -n "$(ls -A "${PATCHES_DIR}/include/linux/" 2>/dev/null)" ]; then
    cp -rvf "${PATCHES_DIR}/include/linux/"* "${KERNEL_ROOT_DIR}/include/linux/"
else
    log_warn "Không có file nào trong ${PATCHES_DIR}/include/linux/ để copy."
fi

# 3. Patch the kernel source
cd "$KERNEL_ROOT_DIR"
KERNEL_PATCH_FILE=$(find "${PATCHES_DIR}" -maxdepth 1 -name "50_add_susfs_in_*.patch" | head -n 1 || true)

if [ -n "$KERNEL_PATCH_FILE" ] && [ -f "$KERNEL_PATCH_FILE" ]; then
    log_info "Áp dụng kernel patch: $(basename "$KERNEL_PATCH_FILE")..."
    # Check if already patched
    if grep -rq "susfs" fs/Makefile 2>/dev/null; then
        log_ok "Kernel dường như đã được patch SUSFS trước đó (tìm thấy susfs trong fs/Makefile)."
    else
        # Try dry-run first
        if patch -p1 --forward --dry-run < "$KERNEL_PATCH_FILE" &>/dev/null; then
            patch -p1 --forward --no-backup-if-mismatch < "$KERNEL_PATCH_FILE"
            log_ok "Áp dụng patch SUSFS vào kernel thành công!"
        else
            log_warn "Patch dry-run phát hiện xung đột, đang thử áp dụng với fuzzy..."
            patch -p1 --forward --no-backup-if-mismatch < "$KERNEL_PATCH_FILE" || {
                log_warn "Một số chunk patch có thể bị reject (.rej). Hãy kiểm tra nếu cần can thiệp thủ công."
            }
        fi
    fi
else
    log_warn "Không tìm thấy file patch 50_add_susfs_in_*.patch trong ${PATCHES_DIR}!"
fi

# 4. Check ReSukiSU compatibility
KSU_DIR="${KERNEL_ROOT_DIR}/KernelSU"
if [ -d "$KSU_DIR" ]; then
    if grep -Eq "KSU_SUSFS|config KSU_SUSFS" "${KSU_DIR}/kernel/Kconfig" 2>/dev/null; then
        log_ok "ReSukiSU đã tích hợp sẵn hỗ trợ KSU_SUSFS, bỏ qua patch KSU riêng!"
    else
        # If vanilla KernelSU is used instead
        KSU_PATCH_FILE="${PATCHES_DIR}/KernelSU/10_enable_susfs_for_ksu.patch"
        if [ -f "$KSU_PATCH_FILE" ]; then
            log_info "Áp dụng 10_enable_susfs_for_ksu.patch cho KernelSU..."
            cd "$KSU_DIR"
            patch -p1 --forward --no-backup-if-mismatch < "$KSU_PATCH_FILE" || log_warn "KSU patch có reject."
            cd "$KERNEL_ROOT_DIR"
        fi
    fi
fi

# 5. Fix ABI protected exports for Android 14+ GKI if present
for abi_file in android/abi_gki_protected_exports_aarch64 android/abi_gki_protected_exports_x86_64; do
    if [ -f "${KERNEL_ROOT_DIR}/${abi_file}" ]; then
        log_info "Xóa ${abi_file} để tránh lỗi module WiFi trên GKI..."
        rm -f "${KERNEL_ROOT_DIR}/${abi_file}"
    fi
done

log_ok "Tích hợp SUSFS hoàn tất!"
