#!/bin/zsh
# Builds a universal .build/SessionBar.app (ad-hoc signed).
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/.build"
APP="$BUILD/SessionBar.app"
BINARIES=()

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
    OUT="$BUILD/binaries/$ARCH/SessionBar"
    mkdir -p "${OUT:h}" "$BUILD/module-cache-$ARCH"
    CLANG_MODULE_CACHE_PATH="$BUILD/module-cache-$ARCH" \
    swiftc "$ROOT"/Sources/SessionBar/*.swift \
        -module-cache-path "$BUILD/module-cache-$ARCH" \
        -target "$ARCH-apple-macosx13.0" \
        -framework AppKit \
        -O -o "$OUT"
    BINARIES+=("$OUT")
done

lipo -create $BINARIES -output "$APP/Contents/MacOS/SessionBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
