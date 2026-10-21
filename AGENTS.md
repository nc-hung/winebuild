# AGENTS.md

Guidance for AI coding agents working in this repo. Human-oriented docs are in [README.md](README.md).

## What this is

Build scripts for running Windows programs on Apple Silicon macOS (developed on macOS 27 with Xcode 27):

- **Wine 11.0**: built as an x86_64 macOS binary that runs under Rosetta 2, in new WoW64 mode
  (`--enable-archs=i386,x86_64`, `--without-x`). That mode runs both 32- and 64-bit Windows programs and installs
  only `wine`, with no `wine64`.
- **MoltenVK 1.4.2**: Vulkan on Metal, built universal. Wine's configure records it as `SONAME_LIBVULKAN`.
- **DXVK-macOS 1.10.3** (Gcenx fork): D3D9/10/11 → Vulkan. DXVK 2.x needs Vulkan features MoltenVK lacks, so
  don't upgrade to it.
- x86_64 freetype, gnutls (with nettle and gmp) and SDL2, built from source because x86_64 Homebrew refuses to
  install on macOS 27.

Out of scope: D3D12 (vkd3d-proton), kernel-level anti-cheat (XIGNCODE3, BattlEye, EAC kernel), and helping
obtain or install pirated software.

## Layout

Tracked in git:

| Path | Purpose |
|---|---|
| `scripts/versions.env` | Single source of pinned versions/tags, tarball URLs + sha256, paths, and helpers (`wb_checkout`, `wb_apply_patches`). Sourced by every build script. |
| `scripts/build-*.sh` | One script per component, each logging to `logs/`. |
| `scripts/wrun` | Launcher; the only supported way to run Wine (see below). |
| `patches/<project>/NNNN-*.patch` | Applied by `wb_apply_patches`; must be safe to apply twice. |
| `demo/*.c` | Small Windows test programs (compiled `.exe` files are ignored). |
| `app/` | Winebuild Manager, a SwiftUI bottle manager (SwiftPM package; see below). |
| `scripts/build-app.sh` | Builds `dist/Winebuild Manager.app` from `app/`. |

Generated and gitignored (never commit): `src/`, `build/`, `dist/`, `deps/`, `logs/`, `prefixes/`, `downloads/`,
`demo/*.exe`, `*.dxvk-cache`, `app/.build/`.

## Build

Run in this order. Each step needs the previous one, and the full chain takes a long time, so run it in the background:

```bash
scripts/build-deps-x86.sh   # -> deps/x86_64
scripts/build-moltenvk.sh   # -> dist/moltenvk (also fetches Vulkan-Headers/Tools used later)
scripts/build-wine.sh       # -> dist/wine   (--no-configure to rebuild only)
scripts/build-dxvk.sh       # -> dist/dxvk/{x64,x32}
scripts/build-tests.sh      # -> demo/vulkaninfo.exe, demo/d3d11tri.exe
```

Requires arm64 Homebrew at `/opt/homebrew` (`bison flex mingw-w64 meson ninja cmake glslang pkgconf gettext`) and
Rosetta 2.

## Run and verify

```bash
scripts/wrun init                                         # create prefix (default prefixes/default)
scripts/wrun -p ~/winebuild/prefixes/NAME program.exe     # or WRUN_PREFIX=...
scripts/wrun --dxvk game.exe                              # DXVK for this run only
scripts/wrun demo/vulkaninfo.exe --summary                # expect Apple GPU, DRIVER_ID_MOLTENVK
scripts/wrun --hud devinfo,fps,version demo/d3d11tri.exe 15
```

Acceptance checks used so far:
- `wine --version` prints `wine-11.0`.
- winecfg and notepad open.
- vulkaninfo lists the Apple GPU.
- d3d11tri reports the Apple adapter and shows the DXVK HUD.

## Winebuild Manager app

`app/` is a SwiftPM package (Swift 6 toolchain, language mode 5, macOS 14+). UI strings are Vietnamese.

- `WineKit` (library, no UI): `Bottle`/`BottleStore` (each folder in `prefixes/` is a bottle),
  `BottleConfig` (stored in `<prefix>/.winebuild/bottle.json`), `WineLauncher` (builds `wrun` command lines),
  `AppScanner` (Start-menu `.lnk` files via `ShellLink`, plus pinned exes), `PEIcon` (icons from PE resources),
  `RegistryFile` (reads `user.reg`/`system.reg`).
- `WinebuildManager` (executable): the SwiftUI app. Every Wine process goes through `scripts/wrun`; logs go to
  `<prefix>/.winebuild/logs/`.
- Settings that Wine reads from the registry (Windows version, Retina, DLL overrides) are written with
  `wine reg add/delete`, so they also apply to plain `wrun` runs. Graphics mode, DXVK HUD, extra environment
  variables and pinned apps live only in `bottle.json` and become `wrun` flags/env when the app launches a program.
- The app finds the repo from the `WinebuildRoot` key that `build-app.sh` writes into Info.plist, falling back to
  `~/winebuild`; Preferences (⌘,) can override it.

```bash
cd app && swift test        # WineKit unit tests (Swift Testing)
scripts/build-app.sh        # -> dist/Winebuild Manager.app (ad-hoc signed); --install copies it to /Applications, --open launches it
```

## Gotchas (learned the hard way)

- **Always go through `wrun`.** Wine's sonames are leaf names. `wrun` sets `DYLD_FALLBACK_LIBRARY_PATH` to
  `dist/wine/lib` and `deps/x86_64/lib`, and without it a bare `dist/wine/bin/wine` can't find MoltenVK,
  freetype or gnutls.
- **cmake/ninja are arm64-only.** Build CMake projects natively with `-DCMAKE_OSX_ARCHITECTURES=x86_64`; don't
  wrap them in `arch -x86_64`.
- **zsh doesn't word-split.** Pass `-p DIR` as separate arguments, or use `WRUN_PREFIX`.
- **Unattended runs.** Set `WINEDLLOVERRIDES="winedbg.exe=d"` so a crash doesn't block on the debugger dialog.
  `wrun` sets `WINEDEBUG=-all` by default; `-v` restores Wine's default debug output.
- **DXVK is per run.** `--dxvk` or `--hud` copies the DLLs into the prefix once and sets `n,b` overrides for that run;
  otherwise the prefix keeps using wined3d.
- **Screenshots.** Wine windows have no bundle ID, so screen-capture tooling that filters by app may not see them. List
  them with CGWindowList (owner `wine`), or ask the user to look.
- **Crash addresses.** For crashes in Rosetta/system code, the dyld shared cache is at the same address in every
  x86_64 process during one boot, so `atos -p <live wine pid> <addr>` symbolizes them.
- **Known failure.** Inno Setup 6.1's stage-2 `.tmp` (seen with a large game installer) can die with
  `nested exception on signal stack` inside `_platform_memmove$VARIANT$Rosetta`. Ordinary 32-bit programs and
  SEH/VEH work (`demo/seh32.c`), so this isn't a general WoW64 problem.
- **Numeric hostname.** When macOS has no HostName set, `hostname` can be a DHCP address such as `192.168.1.20`.
  Unpatched wineboot then crashes in `create_computer_name_keys` (`_invalid_parameter`, 0xc0000417), and a new
  prefix fails with `could not load kernel32.dll`. `patches/wine/0001` fixes this. Check with `hostname`.
- **Fonts.** A fresh prefix has no core fonts. Some glyphs (e.g. Vietnamese capitals with stacked marks) render badly
  in the substituted Courier New; pick a font with full coverage, such as Menlo. Wine's GDI finds macOS's fonts,
  but programs that read font files themselves (Unity's dynamic fonts) look only in `C:\windows\Fonts`, and text
  that needs a fallback (Vietnamese letters beyond Latin-1 in Truy Kích's Unity UI) is simply dropped.
  `wrun fonts-install` symlinks macOS's Arial, Tahoma, Verdana, Times New Roman, Courier New, ... there.
- **Display modes.** winemac's real mode change sets the Mac display's mode for the whole login session when the
  program isn't the active app, so a game's resolution setting stayed on the Mac after the game exited.
  `patches/wine/0004` makes win32u's `EmulateModeset` the default: programs see the mode they asked for, fullscreen
  windows are scaled onto the screen, and the Mac display is never changed (`EmulateModeset`=`N` under
  `HKCU\Software\Wine\X11 Driver` turns real changes back on). Test: `scripts/test-modeset.sh`.
- **Invisible CEF popups.** CEF apps that draw off-screen into a layered window (`UpdateLayeredWindow`) can show a
  fully transparent window that still takes clicks. GPU compositing through ANGLE fails under both wined3d and DXVK
  (DXVK logs `VK_KHR_EXTERNAL_MEMORY_WIN32 not supported` for shared textures). Run without `--dxvk` and add
  `libegl,libglesv2=d` to `WINEDLLOVERRIDES`; the GPU process then fails and CEF falls back to software compositing.
  Seen with the Truy Kích launcher, whose `LiuseLoader.exe` rejects extra CEF switches such as `--disable-gpu`.
- **D3D11-only games under a wined3d launcher.** Unity's D3D11 player (Truy Kích's
  `SSJJ_BattleClient_Unity.exe`, 32-bit) fails with `d3d11: failed to create device and context (80004005)` /
  `InitializeEngineGraphics failed` on wined3d. When the launcher must stay on wined3d (CEF, AIR's D3D9), give
  only the game DXVK with `HKCU\Software\Wine\AppDefaults\<game>.exe\DllOverrides` `d3d11` and `dxgi` =
  `native` (the prefix needs the DXVK DLLs: `wrun dxvk-install`). Don't add `d3d10core`: DXVK doesn't install it
  in syswow64.
- **Input methods.** With a macOS input method such as Vietnamese Telex active, keystrokes can go to Wine's IME
  composition box (a small white box, often at a window's bottom-left) instead of the text field. Switch the input
  source to ABC.
- **Child windows from another process.** A window `SetParent`'ed into another process's window (the Truy Kích
  lobby, Adobe AIR's `ApolloRuntimeContentWindow` inside `SSJJ_MainWnd`) draws nothing in stock Wine.
  `patches/wine/0003` gives it its own Mac window above the parent's; `scripts/test-xproc-child.sh` is the
  two-process regression test (GDI, one-context and two-context OpenGL children). In winemac, find the window that owns the Mac window
  with `get_cocoa_toplevel()`, not `GA_ROOT`: GA_ROOT is the other process's window, and GL/Vulkan client
  surfaces (wined3d, so AIR's D3D9 lobby) attached there leave the child white. A window can also have several GL
  drawables (one per context made current on it; wined3d in AIR makes two), so the drawable that swaps must show
  its own view (`macdrv_client_surface_show`), or frames go to a hidden view and the window is white even when
  it is a normal top-level window. Mouse input must also name the `get_cocoa_toplevel()` window: the server
  asks the named window's thread to set the cursor, and with GA_ROOT the other process set its own (often no)
  cursor, so the pointer vanished over the lobby. A process whose only Mac windows are such children becomes an
  accessory app (`transformProcessToAccessory`), so AIR's lobby process adds no Dock icon of its own. AIR first
  shows an ordinary preloader window and keeps a zero-size one, so a regular app goes back to accessory once only
  such children are shown, and zero-size windows don't make it regular again (test: `splash` mode). A regular
  process left with no window shown (a launcher hiding itself, explorer.exe) becomes accessory after 2 s
  (`transformProcessToAccessoryIfNothingShown`; test: `hide` mode). Don't mark these Mac windows
  `Transient`, since Stage Manager hides transient windows of background apps. The test reports PARTIAL when
  Stage Manager shows windows as scaled thumbnails (positions unchecked) or when the terminal lacks Screen
  Recording permission (the GL child's colour unchecked).

## Conventions for changes

- Bump versions only in `scripts/versions.env`, with sha256 for tarballs, then rebuild the affected components.
- Fixes to upstream sources go in `patches/<project>/` as numbered patches that are safe to re-apply. Don't edit
  `src/` in place.
- Keep each build script's output in `logs/NN-*.log`, and keep scripts `set -euo pipefail`.
- Treat downloaded installers as untrusted. Put each in its own directory under `downloads/` and check the
  Authenticode signer and sha256 before running it. Run installers with their GUI so the user accepts licences themselves.
- Don't use sudo or change system settings without asking the user.
