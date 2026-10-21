#!/bin/bash
# Regression test for patches/wine/0003: a window SetParent'ed into another process's window must still get
# its own Mac window, at the right screen position, above the parent, and follow the parent when it moves.
# Runs demo/xprocchild.exe in prefixes/test (or $WRUN_PREFIX) and checks each phase with check-mac-window.swift,
# with a GDI-painted child and with OpenGL children (one context, and two contexts on the same window as wined3d
# does), whose GL view must show in the child's Mac window
# (checked by colour when the terminal has Screen Recording permission). The child's process must not get a
# Dock icon (it is an accessory app, since its only window is a child of the parent's), also when it first showed
# an ordinary splash window and keeps a zero-size one, as AIR's preloader does ("splash" mode).
# A process that hides its only window (a launcher that hides itself after starting the game) must lose its Dock
# icon too ("hide" mode).
# Last, the mouse is put over the child (needs Accessibility permission, otherwise the script asks you to hover
# it) and the child's process must be the one that sets the cursor, or the pointer can vanish over the child.
set -euo pipefail

WB_ROOT="${WB_ROOT:-$HOME/winebuild}"
export WRUN_PREFIX="${WRUN_PREFIX:-$WB_ROOT/prefixes/test}"
export WINEDLLOVERRIDES="winedbg.exe=d"
exe="$WB_ROOT/demo/xprocchild.exe"
check="$WB_ROOT/scripts/check-mac-window.swift"
log="$(mktemp -t xprocchild)"
trap 'rm -f "$log"' EXIT

if [ ! -f "$exe" ] || [ "$WB_ROOT/demo/xprocchild.c" -nt "$exe" ]; then
    /opt/homebrew/bin/i686-w64-mingw32-gcc -O2 -Wall -o "$exe" "$WB_ROOT/demo/xprocchild.c" -lgdi32 -lopengl32
fi

# wait_phase NAME -> prints "L T" for that phase's expected child position
wait_phase() {
    local i line
    for i in $(seq 1 300); do
        if line=$(grep -m1 "^$1 " "$log"); then
            echo "$line" | sed -E 's/.*child=(-?[0-9]+),(-?[0-9]+).*/\1 \2/'
            return 0
        fi
        grep -q FAIL "$log" && break
        sleep 0.1
    done
    echo "timeout waiting for $1" >&2
    cat "$log" >&2
    return 1
}

# check-mac-window.swift exits 3 when windows are shown scaled and positions can't be checked
fail=0 partial=0
# run_mode MODE [R G B]: MODE is "gdi", "gl", "gl2" (two GL contexts) or "splash"; R G B is the colour the child
# must show
run_mode() {
    local mode=$1 phase x y rc pid
    shift
    : >"$log"
    if [ "$mode" != gdi ]; then "$WB_ROOT/scripts/wrun" "$exe" 8 "$mode" >"$log" 2>&1 &
    else "$WB_ROOT/scripts/wrun" "$exe" 8 >"$log" 2>&1 & fi
    pid=$!
    for phase in phase1 phase2; do
        read -r x y < <(wait_phase "$phase") || { fail=1; break; }
        echo -n "$mode $phase: "
        rc=0
        swift "$check" 301 203 "$x" "$y" 641 457 "$@" || rc=$?
        case $rc in 0) ;; 3) partial=1 ;; *) fail=1 ;; esac
    done
    wait "$pid" || fail=1
    if grep -q "OpenGL setup failed" "$log"; then cat "$log"; fail=1; fi
}
# run_cursor: the child's class cursor is a crosshair, the parent's an arrow; winemac logs the cursor it sets
run_cursor() {
    local x y pid rc=0
    : >"$log"
    WINEDEBUG=+cursor "$WB_ROOT/scripts/wrun" "$exe" 16 >"$log" 2>&1 &
    pid=$!
    if read -r x y < <(wait_phase phase1); then
        swift "$WB_ROOT/scripts/move-mouse.swift" $((x + 150)) $((y + 100)) || rc=$?
        [ $rc = 3 ] && echo "cursor: no Accessibility permission to move the mouse; hover it over the red window now"
    else
        fail=1
    fi
    wait "$pid" || fail=1
    if grep -q "setting cursor with cursor_name crosshairCursor" "$log"; then echo "cursor: PASS"
    elif [ $rc = 3 ]; then echo "cursor: PARTIAL (the mouse never reached the child)"; partial=1
    else echo "cursor: FAIL (the child's process never set its cursor)"; fail=1; fi
}
# run_hide: the process is a regular app while its window shows, an accessory app a few seconds after hiding it
run_hide() {
    local pid wpid i policy
    : >"$log"
    "$WB_ROOT/scripts/wrun" "$exe" 6 hide >"$log" 2>&1 &
    pid=$!
    for i in $(seq 1 300); do grep -q '^hidden' "$log" && break; sleep 0.1; done
    wpid=$(pgrep -f 'xprocchild.exe 6 hide' | head -1 || true)
    sleep 3.5
    policy=$(swift "$WB_ROOT/scripts/app-policy.swift" "${wpid:-0}")
    wait "$pid" || fail=1
    if [ "$policy" = accessory ]; then echo "hide: PASS"
    else echo "hide: FAIL (process ${wpid:-?} with no window shown is '$policy', expected accessory)"; fail=1; fi
}
run_mode gdi
run_mode gl 25 204 51
run_mode gl2 25 204 51
run_mode splash
run_hide
run_cursor
if [ "$fail" != 0 ]; then echo "xprocchild: FAIL"; exit 1; fi
if [ "$partial" != 0 ]; then echo "xprocchild: PARTIAL (windows scaled by the window manager, or no Screen Recording permission)"; exit 3; fi
echo "xprocchild: PASS"
