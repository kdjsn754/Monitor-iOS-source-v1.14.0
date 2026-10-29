#!/bin/bash
# 在 Mac 上直接产出未签名 IPA：./build-unsigned-ipa.sh
# 全程不联网（除首次解析 SwiftPM 依赖），排不上 GitHub 的 macOS 机器时用这个最快。
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  cat <<'EOS'
没找到 XcodeGen。任选一种安装：
  brew install xcodegen
  或下载 https://github.com/yonaskolb/XcodeGen/releases 里的 xcodegen.zip，
  解压后把 xcodegen/bin/xcodegen 与 xcodegen/share 放到同一目录，再软链到 /usr/local/bin。
EOS
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild 不可用：先打开一次 Xcode 接受许可，或执行 sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

# 在 Xcode 26 以下的工具链里，iOS SDK 不认识 iPhone 17 这一代屏幕尺寸，
# 系统会把 App 按兼容模式运行：内容缩在中间，上下各一条黑边。
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 0)"
SDK_MAJOR="${SDK_VERSION%%.*}"
echo "==> iphoneos SDK: $SDK_VERSION"
if [ "${SDK_MAJOR:-0}" -lt 26 ]; then
  cat <<EOS
当前 Xcode 的 iOS SDK 是 $SDK_VERSION，低于 26。
用它打出来的包在 iPhone 17 / iOS 27 上会被系统按兼容模式运行（上下有黑边）。
请换用 Xcode 26 及以上版本（sudo xcode-select -s /Applications/Xcode.app），或改用
GitHub Actions 里的 macos-26 产物。
EOS
  exit 1
fi

xcodegen generate

mkdir -p build
echo "==> 归档（不签名），首次会解析 SwiftPM 依赖，稍等"
xcodebuild archive \
  -project OpenWrtMonitor.xcodeproj \
  -scheme OpenWrtMonitor \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath build/OpenWrtMonitor.xcarchive \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "build/OpenWrtMonitor-$(date +%Y%m%d-%H%M%S).xcresult" \
  -quiet \
  COMPILER_INDEX_STORE_ENABLE=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM=""

APP="build/OpenWrtMonitor.xcarchive/Products/Applications/OpenWrtMonitor.app"
if [ ! -d "$APP" ]; then
  echo "归档完成但没找到 $APP，检查 project.yml 的 target 名是不是 OpenWrtMonitor" >&2
  exit 1
fi

rm -rf build/Payload
mkdir -p build/Payload
cp -R "$APP" build/Payload/
rm -f build/OpenWrtMonitor-unsigned.ipa
(cd build && /usr/bin/ditto -c -k --sequesterRsrc --keepParent Payload OpenWrtMonitor-unsigned.ipa)

echo
echo "IPA: $(pwd)/build/OpenWrtMonitor-unsigned.ipa ($(du -h build/OpenWrtMonitor-unsigned.ipa | cut -f1))"
echo -n "SHA256: "; shasum -a 256 build/OpenWrtMonitor-unsigned.ipa | cut -d' ' -f1
