#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SURFACE_PATHS=(
  OkraPDF/App.swift
  OkraPDF/AppState.swift
  OkraPDF/Brand
  OkraPDF/ContentView.swift
  OkraPDF/Workspace
  OkraPDF/LocalProcessing
)

SWIFT_SURFACE_FILES=()
while IFS= read -r -d '' path; do
  SWIFT_SURFACE_FILES+=("${path}")
done < <(
  find "${SURFACE_PATHS[@]}" \
    -type f \
    -name '*.swift' \
    ! -name 'LocalProviderPaths.swift' \
    ! -name 'BundledResourceLocator.swift' \
    -print0
)

if (( ${#SWIFT_SURFACE_FILES[@]} == 0 )); then
  echo "The desktop brand surface has no Swift files to verify." >&2
  exit 1
fi

if grep -n '"okraPDF' "${SWIFT_SURFACE_FILES[@]}"; then
  echo "Visible desktop copy must not render the okraPDF wordmark." >&2
  exit 1
fi

if ! grep -q 'BrandMarkView(' OkraPDF/Workspace/WorkspaceToolbarContent.swift; then
  echo "The workspace toolbar must render the canonical mark." >&2
  exit 1
fi

echo "Desktop brand surface: mark-only lockup verified"
