#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_PATH="${PROJECT_DIR}/build/azooKeyMac.xcarchive"

echo "=== ビルド開始 ==="
xcodebuild clean archive \
  -project "${PROJECT_DIR}/azooKeyMac.xcodeproj" \
  -scheme azooKeyMac \
  -archivePath "$ARCHIVE_PATH" \
  -configuration Release \
  -allowProvisioningUpdates 2>&1 | tail -3

if [ ! -d "${ARCHIVE_PATH}/Products/Applications/azooKeyMac.app" ]; then
  echo "ERROR: ビルド失敗"
  exit 1
fi

echo "=== ビルド完了 ==="
