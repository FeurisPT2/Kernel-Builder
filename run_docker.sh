#!/usr/bin/env bash
# ==============================================================================
# Helper Script: run_docker.sh
# Purpose: Build kernel inside isolated Docker container
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker &>/dev/null; then
    echo "Lỗi: Không tìm thấy Docker trên hệ thống! Vui lòng cài đặt Docker."
    exit 1
fi

echo "[INFO] Đang build Docker image 'android-kernel-builder'..."
docker build -t android-kernel-builder -f "${SCRIPT_DIR}/docker/Dockerfile" "${SCRIPT_DIR}"

echo "[INFO] Đang chạy container build kernel..."
docker run --rm -it \
    -v "${SCRIPT_DIR}:/workspace" \
    -u "$(id -u):$(id -g)" \
    android-kernel-builder \
    /bin/bash -c "./build.sh --skip-env"
