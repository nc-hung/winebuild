# AGENTS.md

Guidance for AI coding agents working in this repo. Human-oriented docs are in [README.md](README.md).

## What this is

Build scripts for running Windows programs on Apple Silicon macOS (developed on an M5 Pro, macOS 27, Xcode 27):

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

Generated and gitignored (never commit): `src/`, `build/`, `dist/`, `deps/`, `logs/`, `prefixes/`, `downloads/`,
`demo/*.exe`, `*.dxvk-cache`.

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
- **Fonts.** A fresh prefix has no core fonts. Some glyphs (e.g. Vietnamese capitals with stacked marks) render badly
  in the substituted Courier New; pick a font with full coverage, such as Menlo.

## Conventions for changes

- Bump versions only in `scripts/versions.env`, with sha256 for tarballs, then rebuild the affected components.
- Fixes to upstream sources go in `patches/<project>/` as numbered patches that are safe to re-apply. Don't edit
  `src/` in place.
- Keep each build script's output in `logs/NN-*.log`, and keep scripts `set -euo pipefail`.
- Treat downloaded installers as untrusted. Put each in its own directory under `downloads/` and check the
  Authenticode signer and sha256 before running it. Run installers with their GUI so the user accepts licences themselves.
- Don't use sudo or change system settings without asking the user.
