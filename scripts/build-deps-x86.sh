#!/bin/bash
# Build the x86_64 libraries Wine needs (freetype, gnutls+nettle+gmp, SDL2) from source into deps/x86_64.
# Homebrew no longer supports x86_64 on macOS 27, so nothing here needs sudo or /usr/local.
# Everything is configured/compiled under Rosetta (arch -x86_64) so autotools sees a native x86_64 host.
# gettext is only needed for msgfmt at build time; the arm64 Homebrew one is used.
set -euo pipefail
. "$(dirname "$0")/versions.env"

tarballs="$WB_ROOT/deps/tarballs"
srcdir="$WB_ROOT/deps/src"
P="$DEPS_X86"
mkdir -p "$tarballs" "$srcdir" "$P" "$WB_LOGS"
exec > >(tee "$WB_LOGS/00-deps-x86_64.log") 2>&1

export CC="clang -arch x86_64" CXX="clang++ -arch x86_64"
export CPPFLAGS="-I$P/include" LDFLAGS="-L$P/lib"
export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig"
X="arch -x86_64"

fetch() {   # name url sha256 -> extracted source dir on stdout
    local f="$tarballs/$(basename "$2")"
    [ -f "$f" ] || curl -fsSL -o "$f" "$2"
    echo "$3  $f" | shasum -a 256 -c - >&2
    rm -rf "$srcdir/$1"; mkdir -p "$srcdir/$1"
    tar -xf "$f" -C "$srcdir/$1" --strip-components 1
    echo "$srcdir/$1"
}

d=$(fetch gmp "$GMP_URL" "$GMP_SHA256")
# Generic x86_64 asm: Rosetta's reported CPU must not pick unsupported instruction sets.
(cd "$d" && $X ./configure --prefix="$P" --host=x86_64-apple-darwin --enable-shared --disable-static \
    && $X make -j"$JOBS" && $X make install)

d=$(fetch nettle "$NETTLE_URL" "$NETTLE_SHA256")
(cd "$d" && $X ./configure --prefix="$P" --libdir="$P/lib" --enable-shared --disable-static \
    --disable-documentation && $X make -j"$JOBS" && $X make install)

d=$(fetch gnutls "$GNUTLS_URL" "$GNUTLS_SHA256")
(cd "$d" && $X ./configure --prefix="$P" --enable-shared --disable-static \
    --with-included-libtasn1 --with-included-unistring --without-p11-kit --without-idn \
    --without-brotli --without-zstd --without-tpm --without-tpm2 --disable-doc --disable-tests \
    --disable-tools --disable-cxx --disable-guile --disable-nls \
    && $X make -j"$JOBS" && $X make install)

d=$(fetch freetype "$FREETYPE_URL" "$FREETYPE_SHA256")
(cd "$d" && $X ./configure --prefix="$P" --enable-shared --disable-static \
    --with-zlib=yes --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no \
    && $X make -j"$JOBS" && $X make install)

# CMake builds natively and cross-targets x86_64 (cmake/ninja are arm64-only).
d=$(fetch sdl2 "$SDL2_URL" "$SDL2_SHA256")
cmake -S "$d" -B "$WB_BUILD/sdl2-x86_64" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_INSTALL_PREFIX="$P" -DSDL_STATIC=OFF -DSDL_TEST=OFF
ninja -C "$WB_BUILD/sdl2-x86_64" install

for l in libgmp.10 libnettle.8 libhogweed.6 libgnutls.30 libfreetype.6 libSDL2-2.0.0; do
    lipo -info "$P/lib/$l.dylib"
done
