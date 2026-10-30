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

# 打包用的 iOS SDK 决定了 App 在新机型上是铺满还是缩在兼容窗口里：
#   SDK ≤ 26  → 默认兼容档：界面被放进一个旧尺寸窗口居中显示，上下留黑边；
#   SDK 27    → 过渡适配：能铺到屏幕边缘；
#   SDK 27.1+ → 完全适配：真正铺满。
# 低于 26 直接停；26 到 27 之间只警告（能出包，但黑边可能还在）。
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 0)"
SDK_MAJOR="${SDK_VERSION%%.*}"
echo "==> iphoneos SDK: ${SDK_VERSION}（$(xcodebuild -version | head -n 1)）"
if [ "${SDK_MAJOR:-0}" -lt 26 ]; then
  cat <<EOS
当前 Xcode 的 iOS SDK 是 ${SDK_VERSION}，低于 26。
用它打出来的包在新机型上会被系统按兼容模式运行（上下有黑边）。
请换用 Xcode 26 及以上版本（sudo xcode-select -s /Applications/Xcode.app），或改用
GitHub Actions 里的 macos-26 产物。
EOS
  exit 1
fi
if [ "${SDK_MAJOR:-0}" -lt 27 ]; then
  cat <<EOS
注意：SDK 是 ${SDK_VERSION}，低于 27。系统会按「默认兼容」档运行，界面缩在旧尺寸窗口里，
上下仍会留一条黑边。想彻底铺满，请在装有 Xcode 27（iOS 27 SDK）的机器上重新打包。
EOS
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
  echo "归档完成但没找到 ${APP}，检查 project.yml 的 target 名是不是 OpenWrtMonitor" >&2
  exit 1
fi

# 打完之后再核一遍产物里记录的 SDK，避免「检查过了但打出来还是旧包」。
BUILT_SDK="$(/usr/libexec/PlistBuddy -c 'Print :DTSDKName' "$APP/Info.plist" 2>/dev/null || echo 未知)"
echo "==> 产物记录的 SDK: $BUILT_SDK"

# 缺 UILaunchScreen 的包会被系统当成旧版小屏 App，四周强制加黑边。
if /usr/libexec/PlistBuddy -c 'Print :UILaunchScreen' "$APP/Info.plist" >/dev/null 2>&1; then
  echo "==> UILaunchScreen: 有（全屏显示的前提）"
else
  echo "！！产物 Info.plist 里没有 UILaunchScreen，系统会加黑边，请检查 Sources/Info.plist" >&2
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
