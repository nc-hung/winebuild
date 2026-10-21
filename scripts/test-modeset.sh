#!/bin/bash
# Regression test for patches/wine/0004: a program's resolution change (ChangeDisplaySettings, as games do) must
# stay inside Wine. demo/modeset.exe switches to 800x600 and shows a fullscreen window; the Mac display's mode
# must be the same before, during and after, and the window must be scaled to fill the screen's height or width.
# Runs in prefixes/test (or $WRUN_PREFIX).
set -euo pipefail

WB_ROOT="${WB_ROOT:-$HOME/winebuild}"
export WRUN_PREFIX="${WRUN_PREFIX:-$WB_ROOT/prefixes/test}"
export WINEDLLOVERRIDES="winedbg.exe=d"
exe="$WB_ROOT/demo/modeset.exe"
check="$WB_ROOT/scripts/check-modeset.swift"
log="$(mktemp -t modeset)"
trap 'rm -f "$log"' EXIT

if [ ! -f "$exe" ] || [ "$WB_ROOT/demo/modeset.c" -nt "$exe" ]; then
    /opt/homebrew/bin/x86_64-w64-mingw32-gcc -O2 -Wall -o "$exe" "$WB_ROOT/demo/modeset.c" -lgdi32
fi

fail=0
before=$(swift "$check" mode)
"$WB_ROOT/scripts/wrun" "$exe" 4 >"$log" 2>&1 &
pid=$!
for i in $(seq 1 300); do grep -q '^ready\|FAIL' "$log" && break; sleep 0.1; done
if grep -q '^ready' "$log"; then
    during=$(swift "$check" mode)
    read -r ww wh wx wy < <(swift "$check" window) || true
    read -r sw sh _ < <(echo "$before")
    if [ "$during" != "$before" ]; then
        echo "FAIL: the Mac display mode changed to $during (was $before)"; fail=1
    else
        echo "mode: PASS (Mac display stays $sw x $sh while Windows sees 800x600)"
    fi
    if [ "${ww:-none}" = none ]; then
        echo "FAIL: no Wine window on screen"; fail=1
    elif [ $((ww - sw)) -ge -1 ] && [ $((ww - sw)) -le 1 ] || [ $((wh - sh)) -ge -1 ] && [ $((wh - sh)) -le 1 ]; then
        echo "window: PASS (${ww}x${wh} at $wx,$wy fills the ${sw}x${sh} screen)"
    else
        echo "FAIL: fullscreen 800x600 window is ${ww}x${wh} at $wx,$wy on a ${sw}x${sh} screen"; fail=1
    fi
fi
wait "$pid" || fail=1
grep -q '^restored' "$log" || { cat "$log"; fail=1; }
after=$(swift "$check" mode)
[ "$after" = "$before" ] || { echo "FAIL: after exit the Mac display mode is $after (was $before)"; fail=1; }
if [ "$fail" != 0 ]; then echo "modeset: FAIL"; exit 1; fi
echo "modeset: PASS"
