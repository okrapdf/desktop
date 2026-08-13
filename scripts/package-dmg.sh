#!/bin/bash
# Package Okra.app in an install-friendly, intentionally arranged disk image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYOUT_TEMPLATE="${SCRIPT_DIR}/assets/dmg-layout.dsstore.b64"
LAYOUT_SHA256="0eae0115c4a2e16f5ecdf57cff3acf326ef53fd413454581b0c8aa090a0f5222"
VOLUME_NAME="Okra"
APP_NAME="Okra.app"
APPLICATIONS_LINK_NAME="Applications"

WORK_ROOT=""

stage_dmg_contents() {
  local app_path="$1"
  local staging_dir="$2"

  if [[ ! -d "${app_path}" ]]; then
    echo "Missing app bundle: ${app_path}" >&2
    return 1
  fi
  if [[ "$(basename "${app_path}")" != "${APP_NAME}" ]]; then
    echo "Expected an ${APP_NAME} bundle: ${app_path}" >&2
    return 1
  fi

  mkdir -p "${staging_dir}"
  /usr/bin/ditto "${app_path}" "${staging_dir}/${APP_NAME}"
  /bin/ln -s /Applications "${staging_dir}/${APPLICATIONS_LINK_NAME}"
}

cleanup() {
  if [[ -n "${WORK_ROOT}" && -d "${WORK_ROOT}" ]]; then
    /bin/rm -rf "${WORK_ROOT}"
  fi
}

package_dmg() {
  local app_path="$1"
  local output_path="$2"
  local staging_dir
  local read_write_dmg
  local layout_sha256

  if [[ ! -f "${LAYOUT_TEMPLATE}" ]]; then
    echo "Missing Finder layout template: ${LAYOUT_TEMPLATE}" >&2
    return 1
  fi

  mkdir -p "$(dirname "${output_path}")"
  /bin/rm -f "${output_path}"

  WORK_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/okra-dmg.XXXXXX")"
  staging_dir="${WORK_ROOT}/staging"
  read_write_dmg="${WORK_ROOT}/Okra-read-write.dmg"
  trap cleanup EXIT

  stage_dmg_contents "${app_path}" "${staging_dir}"
  /usr/bin/base64 \
    -D \
    -i "${LAYOUT_TEMPLATE}" \
    -o "${staging_dir}/.DS_Store"

  layout_sha256="$(/usr/bin/shasum -a 256 "${staging_dir}/.DS_Store")"
  layout_sha256="${layout_sha256%% *}"
  if [[ "${layout_sha256}" != "${LAYOUT_SHA256}" ]]; then
    echo "Finder layout template checksum mismatch" >&2
    return 1
  fi

  /usr/bin/hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${staging_dir}" \
    -fs HFS+ \
    -ov \
    -format UDRW \
    "${read_write_dmg}" >/dev/null

  /usr/bin/hdiutil convert \
    "${read_write_dmg}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${output_path}" >/dev/null
}

main() {
  if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 /path/to/Okra.app /path/to/Okra-version.dmg" >&2
    exit 64
  fi

  package_dmg "$1" "$2"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
