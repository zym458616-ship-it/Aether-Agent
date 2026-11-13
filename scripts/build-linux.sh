#!/usr/bin/env bash
# Cross-compile Aether for iOS on a Linux host (clang + iPhoneOS SDK + ld64.lld).
# Used by CI; on macOS use scripts/build.sh instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="Aether"
OUT="$ROOT/build"
SDK="${SDK_PATH:-$HOME/sdk/iPhoneOS16.5.sdk}"
MIN_IOS="14.0"

if [ ! -d "$SDK" ]; then
  echo "!! SDK not found at $SDK"
  echo "   run scripts/fetch-sdk.sh first, or set SDK_PATH"
  exit 1
fi

echo "==> SDK : $SDK"
ls "$SDK/System/Library/Frameworks" 2>/dev/null | head -5 || true
clang --version | head -2
(ld64.lld --version 2>/dev/null || echo "ld64.lld not found") | head -2

rm -rf "$OUT"
mkdir -p "$OUT"

SRCS=$(find Sources -name '*.m' | sort)

COMMON=(
  -isysroot "$SDK"
  -I "$ROOT/Sources"
  -fobjc-arc
  -fblocks
  -O2
  -fno-objc-arc-exceptions
  -Wno-deprecated-declarations
  -Wno-nullability-completeness
  -Wno-incompatible-pointer-types
  -Wno-unused-function
  -Wno-unused-variable
  -Wno-unguarded-availability-new
  -Wno-objc-method-access
  -Wno-format
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

build_arch() {
  local ARCH="$1"
  local TARGET="${ARCH}-apple-ios${MIN_IOS}"
  echo "==> compiling $ARCH ($TARGET)"
  clang -target "$TARGET" -dynamiclib "${COMMON[@]}" \
    -fuse-ld=lld \
    -Wl,-install_name,@executable_path/Frameworks/${NAME}.dylib \
    -Wl,-platform_version,ios,${MIN_IOS},16.5 \
    -Wl,-undefined,dynamic_lookup \
    $SRCS "${LIBS[@]}" \
    -o "$OUT/${NAME}-${ARCH}.dylib"
}

build_arch arm64

if build_arch arm64e 2>"$OUT/arm64e.log"; then
  echo "==> arm64e ok"
else
  echo "!! arm64e build failed, continuing arm64-only"
  tail -30 "$OUT/arm64e.log" || true
fi

if [ -f "$OUT/${NAME}-arm64e.dylib" ]; then
  python3 scripts/makefat.py "$OUT/${NAME}.dylib" \
    "$OUT/${NAME}-arm64.dylib" "$OUT/${NAME}-arm64e.dylib"
else
  cp "$OUT/${NAME}-arm64.dylib" "$OUT/${NAME}.dylib"
fi

echo "==> result"
ls -lh "$OUT"/*.dylib
python3 - "$OUT/${NAME}.dylib" <<'PY'
import sys, struct
p = sys.argv[1]
d = open(p, 'rb').read()
magic = struct.unpack('>I', d[:4])[0]
print('magic: %08x  size: %d' % (magic, len(d)))
if magic == 0xcafebabe:
    n = struct.unpack('>I', d[4:8])[0]
    print('fat with %d slices' % n)
    for i in range(n):
        cpu, sub, off, size, align = struct.unpack('>iiIII', d[8+i*20:8+(i+1)*20])
        print('  cputype=%08x subtype=%08x size=%d' % (cpu & 0xffffffff, sub & 0xffffffff, size))
PY
