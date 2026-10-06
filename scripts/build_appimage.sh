#!/usr/bin/env bash
set -euo pipefail

# Script to package SkyStream Linux build into a standalone AppImage.
# Usage:
#   ./scripts/build_appimage.sh [ARCH] [BUNDLE_DIR] [OUTPUT_FILE]
# Example:
#   ./scripts/build_appimage.sh x64 build/linux/x64/release/bundle skystream-linux-x64-v1.0.0.AppImage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ARCH_INPUT="${1:-x64}"
case "${ARCH_INPUT}" in
  x64|x86_64|amd64)
    TARGET_ARCH="x64"
    APPIMAGE_ARCH="x86_64"
    ;;
  arm64|aarch64)
    TARGET_ARCH="arm64"
    APPIMAGE_ARCH="aarch64"
    ;;
  *)
    echo "Unknown architecture: ${ARCH_INPUT}. Defaulting to x86_64."
    TARGET_ARCH="${ARCH_INPUT}"
    APPIMAGE_ARCH="${ARCH_INPUT}"
    ;;
esac

BUNDLE_DIR="${2:-${PROJECT_ROOT}/build/linux/${TARGET_ARCH}/release/bundle}"
OUTPUT_FILE="${3:-${PROJECT_ROOT}/skystream-linux-${TARGET_ARCH}.AppImage}"

# Ensure absolute output path
if [[ "${OUTPUT_FILE}" != /* ]]; then
  OUTPUT_FILE="${PROJECT_ROOT}/${OUTPUT_FILE}"
fi

if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "Error: Bundle directory not found at '${BUNDLE_DIR}'."
  echo "Make sure to run 'flutter build linux --release' first."
  exit 1
fi

if [[ ! -f "${BUNDLE_DIR}/skystream" ]]; then
  echo "Error: 'skystream' binary not found in '${BUNDLE_DIR}'."
  exit 1
fi

echo "==> Packaging SkyStream AppImage for ${TARGET_ARCH} (${APPIMAGE_ARCH})..."
echo "    Bundle Source: ${BUNDLE_DIR}"
echo "    Target Output: ${OUTPUT_FILE}"

APPDIR="$(mktemp -d /tmp/skystream-appdir-XXXXXX)"
cleanup() {
  rm -rf "${APPDIR}"
}
trap cleanup EXIT

# 1. Populate opt/skystream directory with the Flutter bundle
mkdir -p "${APPDIR}/opt/skystream"
cp -r "${BUNDLE_DIR}"/* "${APPDIR}/opt/skystream/"
chmod +x "${APPDIR}/opt/skystream/skystream"

# 2. Add AppRun launcher
cp "${PROJECT_ROOT}/linux/packaging/appimage/AppRun" "${APPDIR}/AppRun"
chmod +x "${APPDIR}/AppRun"

# 3. Add desktop integration entry
mkdir -p "${APPDIR}/usr/share/applications"
cp "${PROJECT_ROOT}/linux/packaging/appimage/skystream.desktop" "${APPDIR}/skystream.desktop"
cp "${PROJECT_ROOT}/linux/packaging/appimage/skystream.desktop" "${APPDIR}/usr/share/applications/skystream.desktop"

# 4. Add SVG icon and .DirIcon
mkdir -p "${APPDIR}/usr/share/icons/hicolor/scalable/apps"
cp "${PROJECT_ROOT}/linux/packaging/appimage/skystream.svg" "${APPDIR}/skystream.svg"
cp "${PROJECT_ROOT}/linux/packaging/appimage/skystream.svg" "${APPDIR}/usr/share/icons/hicolor/scalable/apps/skystream.svg"
ln -sf skystream.svg "${APPDIR}/.DirIcon"

# 5. Add PNG icons
ICON_SRC="${PROJECT_ROOT}/ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon~ios-marketing.png"
if [[ -f "${ICON_SRC}" ]]; then
  cp "${ICON_SRC}" "${APPDIR}/skystream.png"
  for size in 128x128 256x256 512x512; do
    mkdir -p "${APPDIR}/usr/share/icons/hicolor/${size}/apps"
    cp "${ICON_SRC}" "${APPDIR}/usr/share/icons/hicolor/${size}/apps/skystream.png"
  done
fi

# 6. Locate or acquire appimagetool
HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
  x86_64|amd64)
    TOOL_ARCH="x86_64"
    ;;
  aarch64|arm64)
    TOOL_ARCH="aarch64"
    ;;
  *)
    TOOL_ARCH="${HOST_ARCH}"
    ;;
esac

APPIMAGETOOL_BIN="${APPIMAGETOOL:-}"

if [[ -z "${APPIMAGETOOL_BIN}" ]]; then
  CACHE_DIR="${HOME}/.cache/appimagetool/${TOOL_ARCH}"
  APPIMAGETOOL_BIN="${CACHE_DIR}/squashfs-root/AppRun"

  if [[ ! -x "${APPIMAGETOOL_BIN}" ]]; then
    echo "==> Downloading appimagetool for ${TOOL_ARCH}..."
    mkdir -p "${CACHE_DIR}"
    DL_TMP="${CACHE_DIR}/appimagetool.AppImage"
    curl -sL "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${TOOL_ARCH}.AppImage" -o "${DL_TMP}"
    chmod +x "${DL_TMP}"
    (cd "${CACHE_DIR}" && "${DL_TMP}" --appimage-extract >/dev/null)
    rm -f "${DL_TMP}"
  fi
fi

# 7. Generate AppImage
mkdir -p "$(dirname "${OUTPUT_FILE}")"
rm -f "${OUTPUT_FILE}"

echo "==> Running appimagetool..."
ARCH="${APPIMAGE_ARCH}" "${APPIMAGETOOL_BIN}" --no-appstream "${APPDIR}" "${OUTPUT_FILE}"

if [[ -f "${OUTPUT_FILE}" ]]; then
  chmod +x "${OUTPUT_FILE}"
  echo "==> AppImage created successfully: ${OUTPUT_FILE} ($(du -h "${OUTPUT_FILE}" | cut -f1))"
else
  echo "Error: Failed to create AppImage at ${OUTPUT_FILE}"
  exit 1
fi
