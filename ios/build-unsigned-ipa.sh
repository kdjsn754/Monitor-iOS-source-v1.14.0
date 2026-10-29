#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "请先安装 XcodeGen：brew install xcodegen"
  exit 1
fi

xcodegen generate

xcodebuild archive \
  -project OpenWrtMonitor.xcodeproj \
  -scheme OpenWrtMonitor \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath build/OpenWrtMonitor.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM=""

mkdir -p build/Payload
rm -rf build/Payload/OpenWrtMonitor.app
cp -R build/OpenWrtMonitor.xcarchive/Products/Applications/OpenWrtMonitor.app build/Payload/
(cd build && rm -f OpenWrtMonitor-unsigned.ipa && zip -r OpenWrtMonitor-unsigned.ipa Payload)

echo "IPA: $(pwd)/build/OpenWrtMonitor-unsigned.ipa"
