#!/bin/bash
# Build DXVK-macOS (Gcenx fork, works on MoltenVK) for win64 and win32 into dist/dxvk/{x64,x32}.
set -euo pipefail
. "$(dirname "$0")/versions.env"
mkdir -p "$WB_SRC" "$WB_BUILD" "$WB_LOGS"

src="$WB_SRC/dxvk-macos"
wb_checkout "$DXVK_REPO" "$DXVK_TAG" "$src"
wb_apply_patches dxvk-macos "$src"

rm -rf "$WB_DIST/dxvk"
for a in 64 32; do
    b="$WB_BUILD/dxvk$a"
    rm -rf "$b"
    {
        meson setup --cross-file "$src/build-win$a.txt" --buildtype release --strip \
            --prefix "$WB_DIST/dxvk" --bindir "x$a" --libdir "x$a" "$b" "$src"
        ninja -C "$b" install
    } > "$WB_LOGS/03-dxvk$a.log" 2>&1
    echo "dxvk win$a OK"
done
rm -f "$WB_DIST"/dxvk/x*/*.dll.a
ls -l "$WB_DIST"/dxvk/x64 "$WB_DIST"/dxvk/x32
