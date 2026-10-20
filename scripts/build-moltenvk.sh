#!/bin/bash
# Build MoltenVK (universal x86_64+arm64 dylib) and stage it in dist/moltenvk.
set -euo pipefail
. "$(dirname "$0")/versions.env"
mkdir -p "$WB_SRC" "$WB_LOGS"
exec > >(tee "$WB_LOGS/01-moltenvk.log") 2>&1

wb_checkout "$MOLTENVK_REPO" "$MOLTENVK_TAG" "$WB_SRC/MoltenVK"
cd "$WB_SRC/MoltenVK"
./fetchDependencies --macos
make macos

pkg="$WB_SRC/MoltenVK/Package/Release/MoltenVK"
rm -rf "$WB_DIST/moltenvk"
mkdir -p "$WB_DIST/moltenvk/lib"
cp -R "$pkg/dynamic/dylib/macOS/." "$WB_DIST/moltenvk/lib/"
cp -R "$pkg/include" "$WB_DIST/moltenvk/"
lipo -info "$WB_DIST/moltenvk/lib/libMoltenVK.dylib"
echo "MoltenVK $MOLTENVK_TAG -> $WB_DIST/moltenvk"
