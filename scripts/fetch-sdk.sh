#!/usr/bin/env bash
# Fetch an iPhoneOS SDK into ~/sdk using a sparse clone of theos/sdks.
set -euo pipefail

SDK_VER="${SDK_VER:-16.5}"
DEST="${SDK_DEST:-$HOME/sdk}"
NAME="iPhoneOS${SDK_VER}.sdk"

mkdir -p "$DEST"
if [ -d "$DEST/$NAME" ]; then
  echo "==> SDK already present: $DEST/$NAME"
  exit 0
fi

echo "==> sparse-cloning $NAME"
rm -rf "$HOME/sdk-src"
git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git "$HOME/sdk-src"
cd "$HOME/sdk-src"
git sparse-checkout set "$NAME"
cp -a "$NAME" "$DEST/"

echo "==> done"
du -sh "$DEST/$NAME"
ls "$DEST/$NAME" | head
