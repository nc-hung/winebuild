# Patches

The build scripts apply these patches to upstream sources (`wb_apply_patches` in `scripts/versions.env`). Each
patch is safe to apply twice.

Each patch modifies an upstream project and is licensed under that project's license, not under the repository's
MIT License:

| Directory | Upstream | License |
|---|---|---|
| `wine/` | [Wine](https://gitlab.winehq.org/wine/wine) | LGPL-2.1-or-later |
| `dxvk-macos/` | [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | zlib |
| `vulkan-tools/` | [Vulkan-Tools](https://github.com/KhronosGroup/Vulkan-Tools) | Apache-2.0 |

| Patch | What it does |
|---|---|
| `wine/0001` | wineboot: handles a NULL `ai_canonname`. Without it, a Mac whose hostname is an IP address (macOS uses the DHCP address when no HostName is set) can't create a prefix (`could not load kernel32.dll`). |
| `wine/0002` | wow64cpu: switches between 32- and 64-bit code with far returns, which Rosetta 2 handles. Repros: `demo/farjmp32.c`, `demo/flushic32.c`, `demo/ctxrace32.c`. |
| `wine/0003` | winemac/win32u: a window `SetParent`'ed into another process's window now draws, gets mouse input and shows the cursor. Stock Wine draws nothing. Test: `scripts/test-xproc-child.sh`. |
| `wine/0004` | win32u: `EmulateModeset` is on by default, so a game's resolution change no longer changes the Mac display's mode. `HKCU\Software\Wine\X11 Driver\EmulateModeset`=`N` turns real mode changes back on. Test: `scripts/test-modeset.sh`. |
| `dxvk-macos/0001` | Guards the `D3DDEVINFO_RESOURCEMANAGER` typedef, which mingw-w64 11 and later also define. |
| `vulkan-tools/0001` | Makes vulkaninfo load user32 in mingw builds. Upstream loads it only for MSVC, so mingw builds crash. |
