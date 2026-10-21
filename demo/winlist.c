/* Print the window tree as Wine sees it: handle, owning pid, class, title, style, rect, visibility.
 * usage: winlist [pid]   (only windows of that process and their children) */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static DWORD only_pid;

static void dump(HWND hwnd, int depth);

/* EnumChildWindows walks all descendants; only dump direct children here, dump() recurses. */
static BOOL CALLBACK child_proc(HWND hwnd, LPARAM lp)
{
    LONG_PTR *args = (LONG_PTR *)lp;
    if (GetAncestor(hwnd, GA_PARENT) == (HWND)args[1]) dump(hwnd, (int)args[0]);
    return TRUE;
}

static void dump(HWND hwnd, int depth)
{
    char cls[128] = "", title[128] = "";
    DWORD pid = 0;
    RECT r;
    LONG_PTR args[2];

    GetWindowThreadProcessId(hwnd, &pid);
    GetClassNameA(hwnd, cls, sizeof(cls));
    GetWindowTextA(hwnd, title, sizeof(title));
    GetWindowRect(hwnd, &r);
    printf("%*s%p pid %04lx %-28s \"%.40s\" style %08lx ex %08lx (%ld,%ld)-(%ld,%ld) %s\n", depth * 2, "", hwnd, pid, cls,
           title, (unsigned long)GetWindowLongA(hwnd, GWL_STYLE), (unsigned long)GetWindowLongA(hwnd, GWL_EXSTYLE),
           r.left, r.top, r.right, r.bottom, IsWindowVisible(hwnd) ? "visible" : "hidden");
    args[0] = depth + 1;
    args[1] = (LONG_PTR)hwnd;
    EnumChildWindows(hwnd, child_proc, (LPARAM)args);
}

static BOOL CALLBACK top_proc(HWND hwnd, LPARAM lp)
{
    DWORD pid = 0;
    char cls[64] = "";

    GetWindowThreadProcessId(hwnd, &pid);
    GetClassNameA(hwnd, cls, sizeof(cls));
    if (only_pid && pid != only_pid) return TRUE;
    if (!only_pid && !IsWindowVisible(hwnd) && !GetWindow(hwnd, GW_CHILD)) return TRUE;
    dump(hwnd, 0);
    return TRUE;
}

int main(int argc, char **argv)
{
    if (argc > 1) only_pid = strtoul(argv[1], NULL, 0);
    EnumWindows(top_proc, 0);
    return 0;
}
