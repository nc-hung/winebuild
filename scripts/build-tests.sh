#!/bin/bash
# Build the Windows test programs: vulkaninfo.exe (Vulkan-Tools at MoltenVK's pinned revision)
# and the D3D11 triangle demo. Output goes to demo/.
set -euo pipefail
. "$(dirname "$0")/versions.env"
ext="$WB_SRC/MoltenVK/External"
[ -d "$ext/Vulkan-Tools" ] || { echo "run build-moltenvk.sh first (fetches Vulkan-Tools)" >&2; exit 1; }
# Upstream only loads user32 for MSVC builds; mingw builds crash creating the surface window.
wb_apply_patches vulkan-tools "$ext/Vulkan-Tools"

cat > "$WB_BUILD/mingw64.cmake" <<'EOF'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
EOF

{
    cmake -S "$ext/Vulkan-Headers" -B "$WB_BUILD/vulkan-headers" -G Ninja -DCMAKE_INSTALL_PREFIX="$WB_ROOT/deps/vulkan-headers"
    cmake --install "$WB_BUILD/vulkan-headers"
    cmake -S "$ext/Vulkan-Tools" -B "$WB_BUILD/vulkaninfo-win64" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$WB_BUILD/mingw64.cmake" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_CUBE=OFF -DBUILD_ICD=OFF -DBUILD_TESTS=OFF \
        -DCMAKE_PREFIX_PATH="$WB_ROOT/deps/vulkan-headers" -DCMAKE_EXE_LINKER_FLAGS="-static"
    ninja -C "$WB_BUILD/vulkaninfo-win64"
} > "$WB_LOGS/04-tests.log" 2>&1
cp "$WB_BUILD/vulkaninfo-win64/vulkaninfo/vulkaninfo.exe" "$WB_ROOT/demo/"
x86_64-w64-mingw32-strip "$WB_ROOT/demo/vulkaninfo.exe"

x86_64-w64-mingw32-gcc -O2 -o "$WB_ROOT/demo/d3d11tri.exe" "$WB_ROOT/demo/d3d11tri.c" \
    -ld3d11 -ldxgi -ld3dcompiler_47 -luuid -lgdi32 -luser32
x86_64-w64-mingw32-strip "$WB_ROOT/demo/d3d11tri.exe"
ls -l "$WB_ROOT/demo"/*.exe
