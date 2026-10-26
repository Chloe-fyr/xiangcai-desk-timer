#!/bin/zsh
# 编译并打包成 香菜番茄钟.app（Apple 芯片 + Intel 通用），装到 ~/Applications
# 用法：./build.sh          编译并安装
#       ./build.sh --zip    另外打一个发布用的 zip 到 build/
set -e
cd "$(dirname "$0")"
APP="build/香菜番茄钟.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 main.swift -o "build/XiangcaiTimer-$arch"
done
lipo -create build/XiangcaiTimer-arm64 build/XiangcaiTimer-x86_64 -output "$APP/Contents/MacOS/XiangcaiTimer"
rm build/XiangcaiTimer-*
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>香菜番茄钟</string>
  <key>CFBundleDisplayName</key><string>香菜番茄钟</string>
  <key>CFBundleIdentifier</key><string>local.xiangcai.desktimer</string>
  <key>CFBundleExecutable</key><string>XiangcaiTimer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
if [[ "$1" == "--zip" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "build/XiangcaiTimer-macOS.zip"
  echo "发布包：build/XiangcaiTimer-macOS.zip"
fi
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/香菜番茄钟.app"
cp -R "$APP" "$HOME/Applications/"
echo "已装好：$HOME/Applications/香菜番茄钟.app"
