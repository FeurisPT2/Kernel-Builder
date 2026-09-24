#!/usr/bin/env bash
# ==============================================================================
# Script: 01_setup_env.sh
# Purpose: Check and install required host packages for kernel building
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

log_info "Kiểm tra môi trường hệ thống để biên dịch Android Kernel..."

# Detect package manager
if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
else
    PKG_MANAGER="unknown"
fi

REQUIRED_COMMANDS=(
    git curl python3 make bc bison flex
    gcc g++ patch zip unzip tar xz
)

MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [ ${#MISSING_COMMANDS[@]} -eq 0 ]; then
    log_ok "Tất cả các công cụ cơ bản (${REQUIRED_COMMANDS[*]}) đã có sẵn!"
else
    log_warn "Thiếu các công cụ: ${MISSING_COMMANDS[*]}"
    if [ "$PKG_MANAGER" = "apt" ]; then
        log_info "Cài đặt các gói phụ thuộc trên Debian/Ubuntu..."
        SUDO_CMD=""
        if [ "$EUID" -ne 0 ]; then
            if command -v sudo &>/dev/null; then
                SUDO_CMD="sudo"
            else
                log_error "Cần quyền root hoặc sudo để cài đặt gói!"
                exit 1
            fi
        fi

        $SUDO_CMD apt-get update -y
        $SUDO_CMD apt-get install -y --no-install-recommends \
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
            rsync
    elif [ "$PKG_MANAGER" = "pacman" ]; then
        log_info "Cài đặt trên Arch Linux..."
        sudo pacman -Sy --needed --noconfirm base-devel bc bison flex openssl libelf ncurses ccache curl git python zip unzip aarch64-linux-gnu-gcc arm-none-eabi-gcc dtc rsync
    else
        log_warn "Không nhận diện được hệ quản lý gói tự động. Vui lòng đảm bảo các công cụ build đã được cài đặt."
    fi
fi

# Verify essential commands
for cmd in git curl python3 make bc bison flex patch; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Lỗi: Không tìm thấy '$cmd' sau khi cài đặt!"
        exit 1
    fi
done

log_ok "Môi trường hệ thống đã sẵn sàng."
