#!/bin/bash
# 在 Linux 上把 IP, PLEASE 网页游戏打包成 iOS App（.ipa）
# 依赖：clang(含 lld)、iPhoneOS SDK、ldid
set -euo pipefail

cd "$(dirname "$0")"

SDK="${SDK:-/root/.codebuddy/artifact/sdks/iPhoneOS15.6.sdk}"
LDID="${LDID:-/root/.codebuddy/artifact/ldid/ldid}"
MIN_IOS="14.0"
APP_NAME="IPPlease"
OUT="${OUT:-dist/IP-PLEASE.ipa}"

if [ ! -d "$SDK" ]; then
  echo "找不到 iOS SDK: $SDK" >&2
  exit 1
fi

rm -rf build
APP="build/Payload/${APP_NAME}.app"
mkdir -p "$APP"

echo "== 编译 arm64 可执行文件 =="
clang -target arm64-apple-ios${MIN_IOS} \
  -isysroot "$SDK" \
  -fobjc-arc -O2 -Wall -Wno-unused-parameter \
  -fuse-ld=lld \
  -Isrc \
  src/main.m src/saves.m src/httpserver.c \
  -o "$APP/${APP_NAME}" \
  -framework UIKit -framework WebKit -framework Foundation -framework CoreGraphics -framework UniformTypeIdentifiers

echo "== 复制资源 =="
cp -R www "$APP/www"
cp res/icons/*.png "$APP/"
cp Info.plist "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"

echo "== ad-hoc 签名 =="
if [ -x "$LDID" ]; then
  "$LDID" -S "$APP/${APP_NAME}"
else
  echo "警告：未找到 ldid，跳过签名（仍可交给 Sideloadly / AltStore 重签）"
fi

echo "== 打包 ipa =="
mkdir -p "$(dirname "$OUT")"
( cd build && rm -f "$(basename "$OUT")" && zip -qry "$(basename "$OUT")" Payload )
mv "build/$(basename "$OUT")" "$OUT"
echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"
