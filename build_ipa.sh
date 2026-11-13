#!/usr/bin/env bash
#
# build_ipa.sh — Build MagnetBoard and package it as an unsigned .ipa for
# sideloading (AltStore, Sideloadly, TrollStore).
#
# Run this on macOS with Xcode 15 or newer.
#
# Usage:
#   ./build_ipa.sh                      # build + package into ./build/MagnetBoard.ipa
#   TEAM_ID=XXXXXXXXXX ./build_ipa.sh   # build signed with your team
#
set -euo pipefail

PROJECT="MagnetBoard.xcodeproj"
SCHEME="MagnetBoard"
CONFIG="Release"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/MagnetBoard.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
IPA_PATH="${BUILD_DIR}/MagnetBoard.ipa"

echo "==> Cleaning previous build"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

if [[ ! -f "MagnetBoard/Magnet.mfxl" ]]; then
  echo "WARNING: MagnetBoard/Magnet.mfxl is missing." >&2
  echo "         Download it from https://libraries.dev/magnetic (Model tab) and" >&2
  echo "         add it to the MagnetBoard target, or the magnet UI stays dark." >&2
fi

if [[ -n "${TEAM_ID:-}" ]]; then
  echo "==> Archiving (signed) with team ${TEAM_ID}"
  xcodebuild -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -destination "generic/platform=iOS" \
    -archivePath "${ARCHIVE_PATH}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Automatic \
    archive
else
  echo "==> Archiving (unsigned). Set TEAM_ID=... to sign."
  xcodebuild -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -destination "generic/platform=iOS" \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    archive
fi

APP_PATH="${ARCHIVE_PATH}/Products/Applications/MagnetBoard.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: built app not found at ${APP_PATH}" >&2
  exit 1
fi

echo "==> Packaging .ipa"
mkdir -p "${EXPORT_DIR}/Payload"
cp -R "${APP_PATH}" "${EXPORT_DIR}/Payload/"
( cd "${EXPORT_DIR}" && zip -qr "../MagnetBoard.ipa" Payload )

echo "==> Done: ${IPA_PATH}"
ls -lh "${IPA_PATH}"
echo
echo "Sideload ${IPA_PATH} with AltStore / Sideloadly / TrollStore."
