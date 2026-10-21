/* modeset.c - a game-style resolution change must stay inside Wine (test for patches/wine/0004).
 *
 * Switches the primary display to 800x600 with CDS_FULLSCREEN, as games do, checks that Windows sees the new
 * mode, shows a red fullscreen window and prints "ready" with the mode, then restores the mode and prints
 * "restored". scripts/test-modeset.sh checks meanwhile that the Mac display's mode never changes and that the
 * window is scaled to fill the screen.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -Wall -o demo/modeset.exe demo/modeset.c -lgdi32
 * usage: modeset [seconds] */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_PAINT)
    {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        HBRUSH red = CreateSolidBrush(RGB(204, 25, 25));
        FillRect(dc, &ps.rcPaint, red);
        DeleteObject(red);
        EndPaint(hwnd, &ps);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

static void pump(DWORD ms)
{
    DWORD end = GetTickCount() + ms;
    MSG msg;
    while ((LONG)(end - GetTickCount()) > 0)
    {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&msg);
        Sleep(10);
    }
}

int main(int argc, char **argv)
{
    DWORD seconds = argc > 1 ? atoi(argv[1]) : 4;
    DEVMODEA before = {.dmSize = sizeof(before)}, mode = {.dmSize = sizeof(mode)}, now = {.dmSize = sizeof(now)};
    WNDCLASSA wc = {0};
    HWND hwnd;
    LONG ret;

    SetProcessDPIAware();
    EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &before);
    mode.dmPelsWidth = 800;
    mode.dmPelsHeight = 600;
    mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
    if ((ret = ChangeDisplaySettingsA(&mode, CDS_FULLSCREEN)) != DISP_CHANGE_SUCCESSFUL)
    {
        printf("FAIL: ChangeDisplaySettings to 800x600 returned %ld\n", ret);
        return 1;
    }
    EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &now);
    if (now.dmPelsWidth != 800 || now.dmPelsHeight != 600 || GetSystemMetrics(SM_CXSCREEN) != 800)
    {
        printf("FAIL: after the change Windows sees %lux%lu (screen %dx%d)\n", now.dmPelsWidth, now.dmPelsHeight,
               GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
        ChangeDisplaySettingsA(NULL, 0);
        return 1;
    }

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "modeset";
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    RegisterClassA(&wc);
    hwnd = CreateWindowExA(WS_EX_TOPMOST, "modeset", "modeset", WS_POPUP | WS_VISIBLE, 0, 0, 800, 600,
                           NULL, NULL, wc.hInstance, NULL);
    SetForegroundWindow(hwnd);
    pump(700);
    printf("ready mode=%lux%lu was=%lux%lu\n", now.dmPelsWidth, now.dmPelsHeight, before.dmPelsWidth,
           before.dmPelsHeight);
    fflush(stdout);
    pump(seconds * 1000);

    DestroyWindow(hwnd);
    ChangeDisplaySettingsA(NULL, 0);
    EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &now);
    if (now.dmPelsWidth != before.dmPelsWidth || now.dmPelsHeight != before.dmPelsHeight)
    {
        printf("FAIL: restoring left %lux%lu, expected %lux%lu\n", now.dmPelsWidth, now.dmPelsHeight,
               before.dmPelsWidth, before.dmPelsHeight);
        return 1;
    }
    printf("restored\n");
    return 0;
}
