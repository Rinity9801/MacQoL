#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="MacQoL"
BUNDLE="${APP_NAME}.app"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating ${BUNDLE}..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

echo "==> Copying binary..."
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/"

echo "==> Copying Info.plist..."
cp "${APP_NAME}/Info.plist" "${BUNDLE}/Contents/"

echo "==> Copying icon..."
if [ -f "${APP_NAME}.icns" ]; then
    cp "${APP_NAME}.icns" "${BUNDLE}/Contents/Resources/"
else
    echo "    Warning: ${APP_NAME}.icns not found, skipping icon"
fi

echo "==> Signing app..."
IDENTITY=$(security find-identity -v -p codesigning | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "0 valid identities found" ]; then
    codesign --force --deep --sign "$IDENTITY" "${BUNDLE}"
    echo "    Signed with: $IDENTITY"
else
    codesign --force --deep --sign - "${BUNDLE}"
    echo "    Signed ad-hoc (permissions will reset each build)"
fi

echo "==> Done! ${BUNDLE} is ready."
echo "    Run with: open ${BUNDLE}"
echo "    Install with: cp -R ${BUNDLE} /Applications/"
