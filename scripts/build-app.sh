#!/usr/bin/env bash
# Builds ClaudeStats.app — a macOS menu bar app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeStats"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "▶ Building release binary…"
# Prefer a universal (arm64 + x86_64) build; fall back to a native build.
# IMPORTANT: --show-bin-path must use the SAME arch flags as the build, or it
# points at a different (possibly stale) product directory.
ARCH_FLAGS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCH_FLAGS[@]}" 2>/dev/null; then
    ARCH_FLAGS=()
    swift build -c release
fi

BINARY="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BINARY}" ]]; then
    echo "✗ Binary not found at ${BINARY}" >&2
    exit 1
fi

echo "▶ Assembling app bundle at ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BINARY}" "${MACOS}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS}/Info.plist" 2>/dev/null || true
fi

echo "▶ Ad-hoc codesigning…"
codesign --force --deep --sign - "${APP_DIR}"

echo "✓ Built ${APP_DIR}"
echo "  Run: open ${APP_DIR}"
echo "  Install: cp -R ${APP_DIR} /Applications/"
