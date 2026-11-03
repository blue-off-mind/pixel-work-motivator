#!/bin/bash
# 上班激励器 · macOS 构建脚本（只用 Xcode 自带的 swiftc，不需要别的依赖）
#   ./macos/build.sh          编译当前架构 → build/上班激励器.app
#   ./macos/build.sh test     跑计算核心测试
#   ./macos/build.sh run      编译并启动
#   ./macos/build.sh dmg      跑测试 + 编译通用版（Apple 芯片 + Intel）+ 打包 build/上班激励器.dmg
# 签名：默认 ad-hoc；仓库根目录放一个 .codesign-identity（写证书名或 SHA-1）就改用该证书。
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="上班激励器"
EXE="PixelWorkMotivator"
BUILD="build"
APP="$BUILD/$NAME.app"
MIN_OS="12.0"
mkdir -p "$BUILD"

run_tests() {
  swiftc -swift-version 5 macos/Sources/Localization.swift macos/Sources/PayCore.swift macos/Tests/main.swift -o "$BUILD/paycore-tests"
  "$BUILD/paycore-tests"
}

make_icon() {
  if [[ ! -f "$BUILD/AppIcon.icns" || macos/tools/make-icon.swift -nt "$BUILD/AppIcon.icns" ]]; then
    rm -rf "$BUILD/AppIcon.iconset"
    swift macos/tools/make-icon.swift "$BUILD/AppIcon.iconset" >/dev/null
    iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
  fi
}

compile() { # 参数：要编的架构
  local outs=()
  for arch in "$@"; do
    swiftc -swift-version 5 -O -target "$arch-apple-macos$MIN_OS" macos/Sources/*.swift -o "$BUILD/$EXE-$arch"
    outs+=("$BUILD/$EXE-$arch")
  done
  lipo -create -output "$BUILD/$EXE" "${outs[@]}"
}

bundle() {
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BUILD/$EXE" "$APP/Contents/MacOS/$EXE"
  cp macos/Resources/Info.plist "$APP/Contents/Info.plist"
  cp -R macos/Resources/Fonts "$APP/Contents/Resources/Fonts"
  cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  local identity="-"
  [[ -f .codesign-identity ]] && identity="$(tr -d '\n' < .codesign-identity)"
  codesign --force --sign "$identity" "$APP" 2>/dev/null
  echo "✓ $APP"
}

case "${1:-app}" in
  test) run_tests ;;
  app) make_icon; compile "$(uname -m)"; bundle ;;
  run) make_icon; compile "$(uname -m)"; bundle; open "$APP" ;;
  dmg)
    run_tests
    make_icon; compile arm64 x86_64; bundle
    STAGE="$BUILD/dmg"
    rm -rf "$STAGE" "$BUILD/$NAME.dmg"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$BUILD/$NAME.dmg" >/dev/null
    rm -rf "$STAGE"
    echo "✓ $BUILD/$NAME.dmg"
    ;;
  *) echo "用法：$0 [app|test|run|dmg]"; exit 1 ;;
esac
