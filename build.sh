#!/usr/bin/env bash
# ==============================================================================
# Master Script: build.sh
# Purpose: All-in-one runner to build Android Kernel with ReSukiSU + SUSFS
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/config.env"
SKIP_ENV_SETUP=false
DO_CLEAN=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
======================================================================
    _              _           _     _   _  __                    _ 
   / \   _ __   __| |_ __ ___ (_) __| | | |/ /___ _ __ _ __   ___| |
  / _ \ | '_ \ / _` | '__/ _ \| |/ _` | | ' // _ \ '__| '_ \ / _ \ |
 / ___ \| | | | (_| | | | (_) | | (_| | | . \  __/ |  | | | |  __/ |
/_/   \_\_| |_|\__,_|_|  \___/|_|\__,_| |_|\_\___|_|  |_| |_|\___|_|
                     ReSukiSU + SUSFS Auto-Builder
======================================================================
EOF
    echo -e "${NC}"
}

display_usage() {
    show_banner
    echo -e "${BOLD}Cách sử dụng:${NC}"
    echo "  $0 [options]"
    echo ""
    echo -e "${BOLD}Tùy chọn:${NC}"
    echo "  -c, --config <file>   Chỉ định file cấu hình (Mặc định: config/config.env)"
    echo "  -s, --skip-env        Bỏ qua bước cài đặt gói hệ thống (nếu đã cài)"
    echo "  --clean               Xóa thư mục build cũ (out/, work/) trước khi build"
    echo "  -h, --help            Hiển thị trợ giúp này"
    echo ""
    echo -e "${BOLD}Ví dụ:${NC}"
    echo "  $0"
    echo "  $0 --config config/devices/xiaomi_example.env"
    echo "  $0 --skip-env"
    exit 0
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -s|--skip-env)
            SKIP_ENV_SETUP=true
            shift
            ;;
        --clean)
            DO_CLEAN=true
            shift
            ;;
        -h|--help)
            display_usage
            ;;
        *)
            echo -e "${RED}[ERROR] Tham số không hợp lệ: $1${NC}"
            display_usage
            ;;
    esac
done

show_banner

# Check configuration file
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}[WARN] Chưa tìm thấy file cấu hình tại: ${CONFIG_FILE}${NC}"
    if [ -f "${SCRIPT_DIR}/config/config.env.example" ]; then
        echo -e "${BLUE}[INFO] Tự động tạo config/config.env từ template ví dụ...${NC}"
        cp "${SCRIPT_DIR}/config/config.env.example" "${CONFIG_FILE}"
        echo -e "${GREEN}[OK] Đã tạo config/config.env. Vui lòng mở file và chỉnh sửa thông tin kernel của bạn trước khi build!${NC}"
        echo -e "${YELLOW}Chạy 'python3 builder.py' nếu bạn muốn cấu hình tương tác bằng menu.${NC}"
        exit 0
    else
        echo -e "${RED}[ERROR] Không tìm thấy config.env.example!${NC}"
        exit 1
    fi
fi

# Load config
# shellcheck source=/dev/null
source "$CONFIG_FILE"

echo -e "${BOLD}Thông số tiến trình build:${NC}"
echo -e "  * Thiết bị:         ${GREEN}${DEVICE_NAME:-Không xác định} (${DEVICE_MODEL:-})${NC}"
echo -e "  * Nguồn Kernel:     ${CYAN}${KERNEL_SOURCE:-}${NC} [${KERNEL_BRANCH:-default}]"
echo -e "  * Defconfig:        ${YELLOW}${KERNEL_DEFCONFIG:-}${NC}"
echo -e "  * Toolchain:        ${TOOLCHAIN_TYPE:-proton-clang}"
echo -e "  * ReSukiSU:         ${ENABLE_RESUKISU:-true}"
echo -e "  * SUSFS:            ${ENABLE_SUSFS:-true} (${SUSFS_BRANCH:-auto})"
echo -e "  * Đóng gói AnyKernel3: ${ENABLE_ANYKERNEL3:-true}"
echo "----------------------------------------------------------------------"

if [ "$DO_CLEAN" = "true" ]; then
    echo -e "${BLUE}[INFO] Đang làm sạch thư mục out/ và work/...${NC}"
    rm -rf "${SCRIPT_DIR}/out" "${SCRIPT_DIR}/work"
fi

BUILD_ALL_START=$(date +%s)

# Step 1: System environment setup
if [ "$SKIP_ENV_SETUP" = "false" ]; then
    echo -e "\n${BOLD}[1/8] Kiểm tra môi trường hệ thống...${NC}"
    bash "${SCRIPT_DIR}/scripts/01_setup_env.sh"
else
    echo -e "\n${YELLOW}[1/8] Bỏ qua kiểm tra môi trường hệ thống (--skip-env).${NC}"
fi

# Step 2: Fetch toolchain
echo -e "\n${BOLD}[2/8] Chuẩn bị Toolchain Compiler...${NC}"
bash "${SCRIPT_DIR}/scripts/02_fetch_toolchain.sh"

# Step 3: Fetch kernel source
echo -e "\n${BOLD}[3/8] Tải / Kiểm tra mã nguồn Kernel...${NC}"
bash "${SCRIPT_DIR}/scripts/03_fetch_source.sh"

# Step 4: Integrate ReSukiSU
echo -e "\n${BOLD}[4/8] Tích hợp ReSukiSU Root Driver...${NC}"
bash "${SCRIPT_DIR}/scripts/04_integrate_resukisu.sh"

# Step 5: Integrate SUSFS
echo -e "\n${BOLD}[5/8] Tích hợp SUSFS (susfs4ksu)...${NC}"
bash "${SCRIPT_DIR}/scripts/05_integrate_susfs.sh"

# Step 6: Configure Kernel
echo -e "\n${BOLD}[6/8] Áp dụng Defconfig và gộp cấu hình KSU + SUSFS...${NC}"
bash "${SCRIPT_DIR}/scripts/06_configure_kernel.sh"

# Step 7: Compile Kernel
echo -e "\n${BOLD}[7/8] Biên dịch Kernel (make)...${NC}"
bash "${SCRIPT_DIR}/scripts/07_compile_kernel.sh"

# Step 8: Package Kernel into AnyKernel3 ZIP
echo -e "\n${BOLD}[8/8] Đóng gói thành phẩm flashable ZIP...${NC}"
bash "${SCRIPT_DIR}/scripts/08_package_kernel.sh"

BUILD_ALL_END=$(date +%s)
TOTAL_DURATION=$((BUILD_ALL_END - BUILD_ALL_START))
TOTAL_MIN=$((TOTAL_DURATION / 60))
TOTAL_SEC=$((TOTAL_DURATION % 60))

echo ""
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}               BUILD THÀNH CÔNG TẤT CẢ CÁC BƯỚC!                     ${NC}"
echo -e "${GREEN}${BOLD} Tổng thời gian: ${TOTAL_MIN} phút ${TOTAL_SEC} giây                  ${NC}"
echo -e "${GREEN}${BOLD} File flashable ZIP nằm tại: ${SCRIPT_DIR}/output/                   ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
