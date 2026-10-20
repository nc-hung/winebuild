# winebuild

Wine + MoltenVK + DXVK-macOS for Apple Silicon (built and tested on an M5 Pro, macOS 27, Xcode 27).
Wine is an x86_64 build running under Rosetta 2, in new WoW64 mode, so it runs both 32- and 64-bit Windows programs.

Pinned versions live in [scripts/versions.env](scripts/versions.env): MoltenVK v1.4.2, Wine 11.0,
DXVK-macOS v1.10.3-20230507, plus the x86_64 libraries Wine needs (freetype, gnutls, nettle, gmp, SDL2, with sha256).

## Requirements

- Xcode (or the Command Line Tools) and Rosetta 2
- arm64 Homebrew in `/opt/homebrew`:
  `brew install bison flex mingw-w64 meson ninja cmake glslang pkgconf gettext winetricks`

You don't need x86_64 Homebrew, because `build-deps-x86.sh` builds those libraries from source. Homebrew no longer supports x86_64 on macOS 27 anyway.

## Build

Run in this order (each one writes its log to `logs/`):

```bash
scripts/build-deps-x86.sh   # x86_64 freetype/gnutls/SDL2 -> deps/x86_64
scripts/build-moltenvk.sh   # universal libMoltenVK.dylib -> dist/moltenvk
scripts/build-wine.sh       # Wine -> dist/wine (pass --no-configure to rebuild only)
scripts/build-dxvk.sh       # DXVK x64/x32 -> dist/dxvk
scripts/build-tests.sh      # demo/vulkaninfo.exe, demo/d3d11tri.exe
```

Patches in `patches/<project>/` are applied automatically, and applying them twice does no harm:

- `dxvk-macos/0001`: guards the `D3DDEVINFO_RESOURCEMANAGER` typedef, which mingw-w64 11 and later also define.
- `vulkan-tools/0001`: makes vulkaninfo load user32 in mingw builds. Upstream loads it only for MSVC, so mingw builds crash.
- `wine/0001`: stops wineboot crashing when the Mac's hostname is an IP address (macOS uses the DHCP address when
  no HostName is set). Without it, new prefixes fail with `could not load kernel32.dll`.

## Run

Always go through `scripts/wrun`. It sets `WINEPREFIX`, `PATH` and `DYLD_FALLBACK_LIBRARY_PATH`; without the last one, Wine can't find MoltenVK or the x86_64 libs.

```bash
scripts/wrun init                                   # create the prefix (default prefixes/default)
scripts/wrun winecfg
scripts/wrun -p ~/winebuild/prefixes/game setup.exe
scripts/wrun --dxvk game.exe                        # D3D9/10/11 through DXVK instead of wined3d
scripts/wrun --hud devinfo,fps demo/d3d11tri.exe 15 # DXVK HUD
scripts/wrun shell                                  # shell with the Wine environment set
```

DXVK is enabled for each run separately, through `WINEDLLOVERRIDES`; a prefix uses wined3d unless you pass `--dxvk`.

## Checks

- `scripts/wrun demo/vulkaninfo.exe --summary` should list the Apple GPU with `DRIVER_ID_MOLTENVK`.
- `scripts/wrun --hud devinfo,fps,version demo/d3d11tri.exe 15` should show the HUD with the Apple GPU, and the demo prints the adapter it used.

## Out of scope

D3D12 and kernel-level anti-cheat are not supported. DXVK 2.x does not run on MoltenVK, which is why this uses the DXVK-macOS 1.10 fork.
