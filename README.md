# winebuild

Build scripts and a small bottle manager for running Windows programs on Apple Silicon Macs, using only open-source
parts: **Wine**, **MoltenVK** (Vulkan on Metal) and **DXVK-macOS** (Direct3D 9/10/11 on Vulkan).

- Wine is built for x86_64 and runs under Rosetta 2 in new WoW64 mode, so it runs both 32- and 64-bit Windows
  programs without 32-bit macOS libraries.
- Every version is pinned, and tarballs are checked against sha256, so a build can be reproduced.
- Fixes to upstream code live in numbered patches ([patches/](patches/README.md)) that the scripts apply.
- **Winebuild Manager**, a SwiftUI app, manages prefixes ("bottles") the way CrossOver does.

> **Status:** a personal project, tested on macOS 27 with Xcode 27 on Apple Silicon. Expect rough edges. It is not
> affiliated with WineHQ, CodeWeavers, Khronos or Apple.

## Contents

- [What's in the stack](#whats-in-the-stack)
- [Requirements](#requirements)
- [Build](#build)
- [Run programs](#run-programs)
- [Winebuild Manager](#winebuild-manager)
- [Checks and tests](#checks-and-tests)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Repository layout](#repository-layout)
- [Contributing](#contributing)
- [License](#license)

## What's in the stack

```
Windows program (.exe, x86 or x64)
  └─ Wine 11.0 (x86_64, under Rosetta 2)       Windows API
       ├─ winemac.drv                           windows, mouse and keyboard on macOS
       ├─ DXVK-macOS 1.10.3: D3D9/10/11 → Vulkan
       └─ winevulkan → MoltenVK 1.4.2: Vulkan → Metal
```

Pinned versions, source URLs and sha256 sums live in [scripts/versions.env](scripts/versions.env):

| Component | Version | Built by |
|---|---|---|
| Wine | 11.0 | `build-wine.sh` |
| MoltenVK | v1.4.2 (universal) | `build-moltenvk.sh` |
| DXVK-macOS (Gcenx fork) | v1.10.3-20230507 | `build-dxvk.sh` |
| GMP, Nettle, GnuTLS, FreeType, SDL2 (x86_64) | 6.3.0, 3.10.2, 3.8.13, 2.15.0, 2.32.10 | `build-deps-x86.sh` |

DXVK 2.x needs Vulkan features that MoltenVK doesn't have, which is why this uses the DXVK-macOS 1.10 fork.

## Requirements

- An Apple Silicon Mac with Rosetta 2 (`softwareupdate --install-rosetta`)
- Xcode, or the Command Line Tools
- arm64 Homebrew in `/opt/homebrew` with the build tools:

  ```bash
  brew install bison flex mingw-w64 meson ninja cmake glslang pkgconf gettext winetricks
  ```

- About 15 GB of free disk space for sources and build trees

You don't need x86_64 Homebrew. `build-deps-x86.sh` builds the x86_64 libraries Wine needs from source, and Homebrew
no longer installs on x86_64 macOS 27 anyway.

## Build

The scripts expect the repository at `~/winebuild`. To keep it somewhere else, set `WB_ROOT` to its path.

```bash
git clone https://github.com/nc-hung/winebuild.git ~/winebuild
cd ~/winebuild
```

Run the scripts in this order. Each one needs the previous one and writes its log to `logs/`. The full chain takes a
while (Wine is the longest step):

```bash
scripts/build-deps-x86.sh   # x86_64 gmp/nettle/gnutls/freetype/SDL2 -> deps/x86_64
scripts/build-moltenvk.sh   # universal libMoltenVK.dylib            -> dist/moltenvk
scripts/build-wine.sh       # Wine, with MoltenVK                     -> dist/wine (--no-configure to rebuild only)
scripts/build-dxvk.sh       # DXVK 64- and 32-bit DLLs                -> dist/dxvk/{x64,x32}
scripts/build-tests.sh      # demo/vulkaninfo.exe, demo/d3d11tri.exe and the other demos
```

Sources are cloned into `src/`, built in `build/` and installed into `dist/`. All three are gitignored and can be
rebuilt from the scripts.

## Run programs

Always run Wine through `scripts/wrun`. It sets `WINEPREFIX`, `PATH` and `DYLD_FALLBACK_LIBRARY_PATH`; without the
last one, Wine can't find MoltenVK or the x86_64 libraries.

```bash
scripts/wrun init                                    # create the default prefix (prefixes/default)
scripts/wrun winecfg
scripts/wrun -p ~/winebuild/prefixes/game setup.exe  # use another prefix (or set WRUN_PREFIX)
scripts/wrun --dxvk game.exe                         # D3D9/10/11 through DXVK instead of wined3d
scripts/wrun --hud devinfo,fps demo/d3d11tri.exe 15  # DXVK with its HUD
scripts/wrun fonts-install                           # link macOS's core fonts into C:\windows\Fonts
scripts/wrun shell                                   # a shell with the Wine environment set
```

- DXVK is chosen per run. `--dxvk` (or `--hud`) copies the DLLs into the prefix once and sets `n,b` overrides for
  that run only. Otherwise the prefix uses Wine's wined3d.
- `wrun` silences Wine's debug output (`WINEDEBUG=-all`). Pass `-v` to get it back.

## Winebuild Manager

```bash
scripts/build-app.sh --open             # build dist/Winebuild Manager.app and open it
scripts/build-app.sh --install --open   # also copy it to /Applications (Launchpad, Spotlight)
```

A CrossOver-style manager for the prefixes in `prefixes/`. Its interface is in Vietnamese. It can:

- create bottles, run installers (or a file dropped onto the window), and launch installed programs from an icon
  grid;
- pin programs that have no Start-menu shortcut, such as game launchers;
- set, per bottle: WineD3D or DXVK, the DXVK HUD, the Windows version, Retina mode, DLL overrides (with a preset for
  blank CEF launchers) and environment variables;
- open winecfg, regedit, taskmgr and the other Wine tools, and show a log for every program it starts.

Every program goes through `scripts/wrun`. Settings are saved in `<prefix>/.winebuild/bottle.json`. The app is a
SwiftPM package in `app/` (Swift 6 toolchain, macOS 14 or later) and uses no third-party packages.

## Checks and tests

After a build:

```bash
scripts/wrun demo/vulkaninfo.exe --summary                  # should list the Apple GPU with DRIVER_ID_MOLTENVK
scripts/wrun --hud devinfo,fps,version demo/d3d11tri.exe 15 # should show the DXVK HUD with the Apple GPU
```

Regression tests:

| Command | Checks |
|---|---|
| `cd app && swift test` | WineKit unit tests (`.lnk`, PE icon and registry parsing; wrun command lines) |
| `scripts/test-modeset.sh` | A program's resolution change leaves the Mac display alone (`patches/wine/0004`) |
| `scripts/test-xproc-child.sh` | Windows parented into another process draw and get input (`patches/wine/0003`) |

The window tests need Screen Recording and Accessibility permission for the terminal. Without them, some checks
report PARTIAL.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `could not load kernel32.dll` when creating a prefix | The Mac's hostname is an IP address. `patches/wine/0001` fixes it; check with `hostname`. |
| A program can't find `libMoltenVK` / freetype / gnutls | Run it through `scripts/wrun`, not `dist/wine/bin/wine`. |
| Missing or broken letters in a Unity game | `scripts/wrun fonts-install`. Programs that read font files themselves look only in `C:\windows\Fonts`. |
| Typed text goes into a small white box | A macOS input method (such as Vietnamese Telex) is active. Switch the input source to ABC. |
| Blank or invisible window in a CEF launcher | Run without `--dxvk` and add `libegl,libglesv2=d` to `WINEDLLOVERRIDES` so CEF uses software compositing. |
| A Unity D3D11 game fails with `InitializeEngineGraphics failed` | Give only the game DXVK: `HKCU\Software\Wine\AppDefaults\<game>.exe\DllOverrides`, `d3d11` and `dxgi` = `native` (after `wrun dxvk-install`). |
| A crash waits on the debugger dialog | Set `WINEDLLOVERRIDES="winedbg.exe=d"`. |

[AGENTS.md](AGENTS.md) has the full list of gotchas, with the details behind each patch.

## Limitations

- **Direct3D 12** doesn't work. vkd3d-proton needs Vulkan features that MoltenVK lacks.
- **Kernel-level anti-cheat** (XIGNCODE3, BattlEye, EasyAntiCheat in kernel mode) can't run under Wine, so games
  that need it won't start or will be blocked.
- **Rosetta 2:** Apple has said Rosetta will be fully available only through macOS 27. Later macOS versions may
  limit this x86_64 Wine build.
- Expect lower performance than CrossOver, which has its own patches and Apple's D3DMetal.
- Large Inno Setup installers can crash in stage 2 (`nested exception on signal stack`).

## Repository layout

| Path | Contents |
|---|---|
| `scripts/versions.env` | Pinned versions, URLs, sha256 sums and shared helpers |
| `scripts/build-*.sh` | One build script per component |
| `scripts/wrun` | Launcher for every Wine run |
| `scripts/test-*.sh`, `scripts/*.swift` | Window and display regression tests and their helpers |
| `patches/<project>/` | Patches to upstream sources ([details and licenses](patches/README.md)) |
| `demo/*.c` | Small Windows test programs and repros, built by `build-tests.sh` |
| `app/` | Winebuild Manager (SwiftPM package) |
| `AGENTS.md` | Notes for AI coding agents; `CLAUDE.md` imports it |

## Contributing

Issues and pull requests are welcome.

- Change versions only in `scripts/versions.env`, with a sha256 for each tarball.
- Put fixes to upstream code in `patches/<project>/` as numbered patches that are safe to apply twice. Don't edit
  `src/` in place.
- Keep build scripts `set -euo pipefail` and logging to `logs/`.
- Treat downloaded installers as untrusted. Check the Authenticode signer and sha256 before running one.
- This project doesn't help obtain pirated software or get around anti-cheat systems. Only run software you are
  licensed to use.

## License

The scripts, the app, the demos and the documentation are under the [MIT License](LICENSE).

The patches in `patches/` are under their upstream projects' licenses (Wine's patches are LGPL-2.1-or-later). See
[patches/README.md](patches/README.md).

This repository contains no third-party source code or binaries. The build downloads these projects, each under its
own license:

| Project | License |
|---|---|
| [Wine](https://gitlab.winehq.org/wine/wine) | LGPL-2.1-or-later |
| [MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Apache-2.0 |
| [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | zlib |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) / [Vulkan-Tools](https://github.com/KhronosGroup/Vulkan-Tools) | Apache-2.0 (Vulkan-Headers: Apache-2.0 or MIT) |
| [SDL2](https://github.com/libsdl-org/SDL) | zlib |
| [FreeType](https://freetype.org) | FreeType License (FTL) or GPL-2.0 |
| [GnuTLS](https://gnutls.org) | LGPL-2.1-or-later |
| [Nettle](https://www.lysator.liu.se/~nisse/nettle/), [GMP](https://gmplib.org) | LGPL-3.0-or-later or GPL-2.0-or-later |

If you distribute built binaries (the contents of `dist/` or `deps/`), you must follow those licenses. For the LGPL
parts, that means shipping or offering the corresponding source, including the patches here, and letting users
replace the LGPL libraries.
