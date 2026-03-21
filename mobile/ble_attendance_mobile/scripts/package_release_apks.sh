#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BLE_Attendance"
VERSION_ITERATION="${1:-v0.1.3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${PROJECT_DIR}/build/app/outputs/flutter-apk"

SRC_ARM64="${OUT_DIR}/app-arm64-v8a-release.apk"
SRC_ARM32="${OUT_DIR}/app-armeabi-v7a-release.apk"

if [[ ! -f "${SRC_ARM64}" || ! -f "${SRC_ARM32}" ]]; then
  echo "Release split APKs not found. Build first with:"
  echo "flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64"
  exit 1
fi

DST_ARM64="${OUT_DIR}/${APP_NAME}_${VERSION_ITERATION}_arm64-v8a_release.apk"
DST_ARM32="${OUT_DIR}/${APP_NAME}_${VERSION_ITERATION}_armeabi-v7a_release.apk"

cp "${SRC_ARM64}" "${DST_ARM64}"
cp "${SRC_ARM32}" "${DST_ARM32}"

echo "Packaged APKs:"
echo "- ${DST_ARM64}"
echo "- ${DST_ARM32}"
