#!/usr/bin/env bash
# Aether - build script (macOS + Xcode command line tools required)
# Produces build/Aether.dylib (fat: arm64 + arm64e), injectable into any app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="Aether"
OUT="$ROOT/build"
MIN_IOS="14.0"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

echo "==> SDK: $SDK"
xcrun --sdk iphoneos --show-sdk-version

rm -rf "$OUT"
mkdir -p "$OUT"

SRCS=$(find Sources -name '*.m' | sort)
if [ -z "$SRCS" ]; then echo "no sources"; exit 1; fi

COMMON=(
  -dynamiclib
  -fobjc-arc
  -fmodules
  -fblocks
  -O2
  -g0
  -isysroot "$SDK"
  -I"$ROOT/Sources"
  -install_name "@executable_path/Frameworks/${NAME}.dylib"
  -Wno-deprecated-declarations
  -Wno-unused-variable
  -Wno-unused-function
  -Wno-nullability-completeness
  -Wno-incompatible-pointer-types
  -Wno-objc-method-access
  -Wno-unguarded-availability-new
)

LIBS=(
  -framework Foundation
  -framework UIKit
  -framework CoreGraphics
  -framework QuartzCore
  -framework IOKit
  -framework Security
  -framework ImageIO
  -lsqlite3
)

for ARCH in arm64 arm64e; do
  echo "==> compiling $ARCH"
  xcrun --sdk iphoneos clang -target "${ARCH}-apple-ios${MIN_IOS}" \
    "${COMMON[@]}" $SRCS "${LIBS[@]}" -o "$OUT/${NAME}-${ARCH}.dylib"
done

echo "==> lipo"
xcrun lipo -create -output "$OUT/${NAME}.dylib" \
  "$OUT/${NAME}-arm64.dylib" "$OUT/${NAME}-arm64e.dylib"

echo "==> codesign (ad-hoc)"
codesign --force --sign - --timestamp=none "$OUT/${NAME}.dylib"

echo "==> result"
xcrun lipo -info "$OUT/${NAME}.dylib"
ls -lh "$OUT/${NAME}.dylib"
