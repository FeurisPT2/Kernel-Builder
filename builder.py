#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Android Kernel Auto-Builder Wizard
Trình hướng dẫn thiết lập và biên dịch Android Kernel tích hợp ReSukiSU & SUSFS
"""

import os
import sys
import subprocess

BOLD = "\033[1m"
GREEN = "\033[0;32m"
BLUE = "\033[0;34m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
RED = "\033[0;31m"
NC = "\033[0m"

ASCII_ART = r"""
======================================================================
    _              _           _     _   _  __                    _ 
   / \   _ __   __| |_ __ ___ (_) __| | | |/ /___ _ __ _ __   ___| |
  / _ \ | '_ \ / _` | '__/ _ \| |/ _` | | ' // _ \ '__| '_ \ / _ \ |
 / ___ \| | | | (_| | | | (_) | | (_| | | . \  __/ |  | | | |  __/ |
/_/   \_\_| |_|\__,_|_|  \___/|_|\__,_| |_|\_\___|_|  |_| |_|\___|_|
                     ReSukiSU + SUSFS Auto-Builder
======================================================================
"""
BANNER = f"{CYAN}{BOLD}{ASCII_ART}{NC}"


def prompt(question, default=""):
    if default:
        res = input(f"{BOLD}{question}{NC} [{CYAN}{default}{NC}]: ").strip()
        return res if res else default
    else:
        while True:
            res = input(f"{BOLD}{question}{NC}: ").strip()
            if res:
                return res

def prompt_bool(question, default=True):
    choice_str = "Y/n" if default else "y/N"
    res = input(f"{BOLD}{question}{NC} [{CYAN}{choice_str}{NC}]: ").strip().lower()
    if not res:
        return default
    return res in ["y", "yes", "true", "1"]

def main():
    print(BANNER)
    print(f"{BOLD}Chào mừng bạn đến với Android Kernel Auto-Builder!{NC}")
    print("Công cụ này sẽ giúp bạn cấu hình dự án để tự động build kernel tích hợp ReSukiSU và SUSFS.\n")

    presets = [
        ("Tự nhập thông tin thiết bị (Custom)", None),
        ("Xiaomi Snapdragon 865 / SM8250 (Kernel 4.19) - Ví dụ: POCO F3, K40", "config/devices/xiaomi_example.env"),
        ("Android Generic Kernel Image (GKI 2.0 - Kernel 5.10 / 5.15)", "config/devices/gki_example.env"),
    ]

    print(f"{YELLOW}--- Chọn cấu hình bắt đầu ---{NC}")
    for idx, (desc, _) in enumerate(presets, 1):
        print(f"  {idx}. {desc}")

    choice = input(f"\nNhập lựa chọn [1-{len(presets)}] [{CYAN}1{NC}]: ").strip() or "1"
    
    config = {}
    preset_file = None
    if choice == "2":
        preset_file = presets[1][1]
    elif choice == "3":
        preset_file = presets[2][1]

    if preset_file and os.path.exists(preset_file):
        print(f"{GREEN}[OK] Sử dụng cấu hình mẫu: {preset_file}{NC}")
        with open(preset_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip().strip('"').strip("'")

    # Interactive questionnaire
    print(f"\n{YELLOW}--- Cấu hình thiết bị & Kernel ---{NC}")
    device_name = prompt("1. Mã thiết bị (Device Codename, vd: alioth, sweet, vayu)", config.get("DEVICE_NAME", "my_device"))
    device_model = prompt("2. Tên thương mại (Device Model, vd: POCO F3)", config.get("DEVICE_MODEL", "Android Phone"))
    kernel_source = prompt("3. Link Git Repository mã nguồn Kernel", config.get("KERNEL_SOURCE", ""))
    kernel_branch = prompt("4. Nhánh Git (Branch) của Kernel", config.get("KERNEL_BRANCH", "main"))
    kernel_defconfig = prompt("5. Tên file defconfig (trong arch/arm64/configs/)", config.get("KERNEL_DEFCONFIG", "vendor/kona-perf_defconfig"))

    print(f"\n{YELLOW}--- Cấu hình Trình biên dịch (Toolchain) ---{NC}")
    print("  1. Proton Clang (Khuyên dùng cho Non-GKI 4.14, 4.19, 5.4)")
    print("  2. AOSP Clang (Khuyên dùng cho GKI 5.10, 5.15, 6.1)")
    tc_choice = input(f"Chọn toolchain [1-2] [{CYAN}1{NC}]: ").strip() or "1"
    if tc_choice == "2":
        toolchain_type = "aosp-clang"
        clang_version = prompt("Nhập phiên bản AOSP Clang (vd: r450784d, r487747c, r510928)", config.get("AOSP_CLANG_VERSION", "r450784d"))
    else:
        toolchain_type = "proton-clang"
        clang_version = "r450784d"

    print(f"\n{YELLOW}--- Cấu hình Tính năng Root & Ẩn Root ---{NC}")
    enable_resukisu = prompt_bool("Tích hợp ReSukiSU Root Driver vào Kernel?", config.get("ENABLE_RESUKISU", "true").lower() == "true")
    enable_susfs = prompt_bool("Tích hợp SUSFS (susfs4ksu) để vượt kiểm tra Root?", config.get("ENABLE_SUSFS", "true").lower() == "true")
    
    susfs_branch = "auto"
    if enable_susfs:
        susfs_branch = prompt("Nhánh SUSFS (nhập 'auto' để tự động phát hiện phiên bản kernel)", config.get("SUSFS_BRANCH", "auto"))

    print(f"\n{YELLOW}--- Cấu hình Đóng gói ---{NC}")
    enable_ak3 = prompt_bool("Đóng gói thành file flashable ZIP qua AnyKernel3?", config.get("ENABLE_ANYKERNEL3", "true").lower() == "true")
    image_name = prompt("Tên file Kernel Image đích (Image, Image.gz, Image.gz-dtb)", config.get("KERNEL_IMAGE_NAME", "Image.gz-dtb"))

    # Write config to config/config.env
    os.makedirs("config", exist_ok=True)
    config_path = "config/config.env"
    with open(config_path, "w", encoding="utf-8") as f:
        f.write(f"""# Generated by builder.py
DEVICE_NAME="{device_name}"
DEVICE_MODEL="{device_model}"
KERNEL_SOURCE="{kernel_source}"
KERNEL_BRANCH="{kernel_branch}"
KERNEL_DEFCONFIG="{kernel_defconfig}"
ARCH="arm64"
SUBARCH="arm64"
TOOLCHAIN_TYPE="{toolchain_type}"
AOSP_CLANG_VERSION="{clang_version}"
LLVM="1"
ENABLE_RESUKISU={"true" if enable_resukisu else "false"}
RESUKISU_REPO="https://github.com/ReSukiSU/ReSukiSU.git"
RESUKISU_BRANCH="main"
ENABLE_SUSFS={"true" if enable_susfs else "false"}
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_BRANCH="{susfs_branch}"
ENABLE_ANYKERNEL3={"true" if enable_ak3 else "false"}
ANYKERNEL3_REPO="https://github.com/osm0sis/AnyKernel3.git"
ANYKERNEL3_BRANCH="master"
KERNEL_IMAGE_NAME="{image_name}"
BUILD_DTBO=false
EXTRA_MAKE_FLAGS=""
""")

    print(f"\n{GREEN}[OK] Đã lưu cấu hình vào: {config_path}{NC}\n")

    if prompt_bool("Bạn có muốn bắt đầu quá trình biên dịch (./build.sh) ngay bây giờ?", default=True):
        print(f"\n{CYAN}>>> Khởi chạy ./build.sh...{NC}\n")
        subprocess.run(["bash", "./build.sh"], check=False)
    else:
        print(f"\nBạn có thể chạy build bất cứ lúc nào bằng lệnh: {BOLD}./build.sh{NC}")
        print(f"Hoặc đẩy repository lên GitHub để build tự động qua {BOLD}GitHub Actions{NC}!")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Đã hủy thao tác bởi người dùng.{NC}")
        sys.exit(0)
