#!/bin/bash
# Build Wine (x86_64 host, new WoW64: i386+x86_64 PE) under Rosetta, out-of-tree, into dist/wine.
# Needs: build-moltenvk.sh and build-deps-x86.sh done first. gettext (msgfmt) comes from arm64 Homebrew.
set -euo pipefail
. "$(dirname "$0")/versions.env"
mkdir -p "$WB_SRC" "$WB_BUILD" "$WB_LOGS"

src="$WB_SRC/wine"
bld="$WB_BUILD/wine64"
mvk="$WB_DIST/moltenvk"
prefix="$WB_DIST/wine"
[ -f "$mvk/lib/libMoltenVK.dylib" ] || { echo "run build-moltenvk.sh first" >&2; exit 1; }

wb_checkout "$WINE_REPO" "$WINE_TAG" "$src"
wb_apply_patches wine "$src"

# Only deps/x86_64 may be visible to configure; never /opt/homebrew (arm64) libs.
[ -f "$DEPS_X86/lib/libgnutls.30.dylib" ] || { echo "run build-deps-x86.sh first" >&2; exit 1; }
export PKG_CONFIG_LIBDIR="$DEPS_X86/lib/pkgconfig"
export CPPFLAGS="-I$DEPS_X86/include -I$mvk/include"
export LDFLAGS="-L$DEPS_X86/lib -L$mvk/lib"
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64"

if [ "${1:-}" != "--no-configure" ]; then
    rm -rf "$bld"; mkdir -p "$bld"
    (cd "$bld" && arch -x86_64 "$src/configure" --prefix="$prefix" \
        --enable-archs=i386,x86_64 --without-x --disable-tests) 2>&1 | tee "$WB_LOGS/02-wine-configure.log"

    # Hard requirements: fail now rather than ship a Wine without fonts/TLS/Vulkan.
    missing=0
    # On macOS, a found MoltenVK is recorded as SONAME_LIBVULKAN.
    for m in SONAME_LIBFREETYPE SONAME_LIBGNUTLS SONAME_LIBVULKAN; do
        if ! grep -q "#define $m " "$bld/include/config.h"; then echo "configure: $m not found" >&2; missing=1; fi
    done
    [ $missing = 0 ] || exit 1
    grep -E '#define SONAME_LIB(FREETYPE|GNUTLS|VULKAN|SDL2) ' "$bld/include/config.h"
fi

arch -x86_64 make -C "$bld" -j"$JOBS" > "$WB_LOGS/02-wine-make.log" 2>&1 || { tail -40 "$WB_LOGS/02-wine-make.log"; exit 1; }
rm -rf "$prefix"
arch -x86_64 make -C "$bld" install > "$WB_LOGS/02-wine-install.log" 2>&1

# Ship MoltenVK next to Wine's unix libs so dlopen finds it without system installs.
cp "$mvk/lib/libMoltenVK.dylib" "$prefix/lib/"
"$prefix/bin/wine" --version
