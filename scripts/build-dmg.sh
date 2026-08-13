#!/bin/bash
# Build Okra.app and package as DMG
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
# CFBundleVersion must be a monotonically increasing integer for Sparkle
# (sparkle:version). Default: UTC timestamp to the minute; release automation
# passes the same value it records in appcast.xml.
BUILD_NUMBER="${2:-$(date -u +%Y%m%d%H%M)}"
PACKAGE_MODE="${3:-}"
if [[ -n "${PACKAGE_MODE}" && "${PACKAGE_MODE}" != "--app-only" ]]; then
  echo "usage: $0 [version] [build-number] [--app-only]" >&2
  exit 64
fi
APP_NAME="Okra"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
APP_DIR="build/${APP_NAME}.app/Contents"
SPARKLE_FRAMEWORK_SOURCE=".build/release/Sparkle.framework"
SPARKLE_FEED_URL="https://raw.githubusercontent.com/okra-project/desktop/main/appcast.xml"
SPARKLE_PUBLIC_ED_KEY="boNvfEtcUxucfd8O1dSCbf5ovggYVAGzgF03Ou4LBBs="
ICON_SOURCE="OkraPDF/AppIcon.png"
ICON_NAME="AppIcon.icns"
ICON_TMP_ROOT="$(mktemp -d /private/tmp/okra-icon.XXXXXX)"
ICON_PNG="${ICON_TMP_ROOT}/okra-logo-source.png"
ROUNDED_ICON_PNG="${ICON_TMP_ROOT}/okra-logo-rounded.png"
ICONSET_DIR="${ICON_TMP_ROOT}/AppIcon.iconset"

cleanup() {
  rm -rf "${ICON_TMP_ROOT}"
}
trap cleanup EXIT

echo "Building ${APP_NAME} v${VERSION}..."
swift build -c release 2>&1 | tail -3

rm -rf "build/${APP_NAME}.app"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources" "$APP_DIR/Frameworks"
cp .build/release/Okra "$APP_DIR/MacOS/${APP_NAME}"
cp -R .build/release/okraPDF_Okra.bundle "$APP_DIR/Resources/"

# Embed Sparkle (in-app updater) and point the loader at Contents/Frameworks.
if [[ ! -d "${SPARKLE_FRAMEWORK_SOURCE}" ]]; then
  echo "Missing Sparkle framework: ${SPARKLE_FRAMEWORK_SOURCE}" >&2
  exit 1
fi
ditto "${SPARKLE_FRAMEWORK_SOURCE}" "$APP_DIR/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/MacOS/${APP_NAME}" 2>/dev/null || true

# Normalize the source asset to a real PNG before building the icns.
if [[ ! -f "${ICON_SOURCE}" ]]; then
  echo "Missing app icon source: ${ICON_SOURCE}" >&2
  exit 1
fi

sips -s format png "${ICON_SOURCE}" --out "${ICON_PNG}" >/dev/null
swift scripts/render-app-icon.swift "${ICON_PNG}" "${ROUNDED_ICON_PNG}" >/dev/null
mkdir -p "${ICONSET_DIR}"
for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${ROUNDED_ICON_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "${retina}" "${retina}" "${ROUNDED_ICON_PNG}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET_DIR}" -o "$APP_DIR/Resources/${ICON_NAME}"

# Generate Info.plist with version
cat > "$APP_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Okra</string>
    <key>CFBundleIdentifier</key>
    <string>com.okrapdf.desktop</string>
    <key>CFBundleName</key>
    <string>Okra</string>
    <key>CFBundleDisplayName</key>
    <string>Okra</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Local builds remain ad-hoc signed. Release automation provides a Developer ID
# Application identity and enables the hardened runtime plus a secure timestamp.
# Sparkle ships its helper binaries (Autoupdate, Updater.app, XPC services)
# unsigned: sign every component inside-out or notarization rejects the app.
SPARKLE_FW="build/${APP_NAME}.app/Contents/Frameworks/Sparkle.framework"
sign_sparkle_component() {
  local component="$1"
  shift
  if [[ -e "${component}" ]]; then
    codesign --force "$@" "${component}"
  fi
}
if [[ -n "${SIGNING_IDENTITY}" ]]; then
  for component in \
    "${SPARKLE_FW}/Versions/Current/XPCServices/Installer.xpc" \
    "${SPARKLE_FW}/Versions/Current/XPCServices/Downloader.xpc" \
    "${SPARKLE_FW}/Versions/Current/Autoupdate" \
    "${SPARKLE_FW}/Versions/Current/Updater.app" \
    "${SPARKLE_FW}"; do
    sign_sparkle_component "${component}" \
      --options runtime \
      --timestamp \
      --sign "${SIGNING_IDENTITY}"
  done
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "${SIGNING_IDENTITY}" \
    --entitlements okraPDF.entitlements \
    "build/${APP_NAME}.app"
else
  for component in \
    "${SPARKLE_FW}/Versions/Current/XPCServices/Installer.xpc" \
    "${SPARKLE_FW}/Versions/Current/XPCServices/Downloader.xpc" \
    "${SPARKLE_FW}/Versions/Current/Autoupdate" \
    "${SPARKLE_FW}/Versions/Current/Updater.app" \
    "${SPARKLE_FW}"; do
    sign_sparkle_component "${component}" --sign -
  done
  codesign --force --sign - --entitlements okraPDF.entitlements "build/${APP_NAME}.app"
fi

APP_SIZE=$(du -sh "build/${APP_NAME}.app" | cut -f1)
if [[ "${PACKAGE_MODE}" == "--app-only" ]]; then
  echo ""
  echo "${APP_NAME} v${VERSION}"
  echo "  .app: ${APP_SIZE} (build/${APP_NAME}.app)"
  exit 0
fi

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG="build/${DMG_NAME}"
./scripts/package-dmg.sh "build/Okra.app" "${DMG}"

DMG_SIZE=$(du -sh "${DMG}" | cut -f1)
echo ""
echo "${APP_NAME} v${VERSION}"
echo "  .app: ${APP_SIZE} (build/${APP_NAME}.app)"
echo "  .dmg: ${DMG_SIZE} (build/${DMG_NAME})"
