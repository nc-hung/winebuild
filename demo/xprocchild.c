/* Regression test for windows reparented into a window of another process, the way Adobe AIR's lobby window
 * (ApolloRuntimeContentWindow) is SetParent'ed into the launcher's main window.
 *
 * The parent process shows a 641x457 popup and starts a copy of itself with "child <hwnd>". The child creates
 * an overlapped 301x203 window, SetParents it into the parent's window at client (50,50) and paints it.
 * The parent then logs phases on stdout:
 *   phase1 child=L,T     child window shown; L,T is where it should be on screen
 *   phase2 child=L,T     parent moved by (+60,+40) and raised; the child should have followed
 * scripts/test-xproc-child.sh checks with CGWindowList that a 301x203 Mac window exists at L,T in each phase
 * and is ordered above the parent's window.
 * With "gl", the child also draws green with OpenGL after SetParent, over its red GDI background, the way AIR
 * renders the lobby with D3D9 (wined3d uses GL/Vulkan client surfaces). Red on screen means the GL view never
 * reached the child's Mac window (the white-lobby bug).
 * With "gl2", the child also makes a second GL context current on the window before drawing with the first,
 * the way wined3d does in AIR. win32u gives the second context its own drawable, and winemac used to show that
 * drawable's empty view and hide the one being drawn to.
 * With "splash", the child first shows an ordinary popup (like AIR's preloader window) and keeps a visible
 * zero-size window, then hides the popup before SetParent. Its process must still end up without a Dock icon.
 * With "hide", no child is started: the window is shown, then hidden ("shown", "hidden" on stdout), and the
 * process stays alive with nothing on screen. A couple of seconds later it must no longer have a Dock icon,
 * like a launcher that hides itself after starting the game.
 * The child's class cursor is a crosshair and the parent's an arrow. With the mouse over the child's Mac window,
 * the child's process must be the one asked to set the cursor: the test runs with WINEDEBUG=+cursor and looks
 * for winemac setting "crosshairCursor". Before the fix the parent's process was asked, with its own cursor,
 * and the pointer could vanish over the child.
 * build: i686-w64-mingw32-gcc -O2 -Wall -o demo/xprocchild.exe demo/xprocchild.c -lgdi32 -lopengl32
 * usage: xprocchild [seconds] [gl|gl2|splash|hide] */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>

#define PARENT_W 641
#define PARENT_H 457
#define CHILD_W  301
#define CHILD_H  203
#define CHILD_X  50
#define CHILD_Y  50

static COLORREF color;
static HDC gl_dc;

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    PAINTSTRUCT ps;
    HBRUSH brush;

    switch (msg)
    {
    case WM_PAINT:
        BeginPaint(hwnd, &ps);
        brush = CreateSolidBrush(color);
        FillRect(ps.hdc, &ps.rcPaint, brush);
        DeleteObject(brush);
        EndPaint(hwnd, &ps);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

static void pump(DWORD ms)
{
    DWORD end = GetTickCount() + ms;
    MSG msg;

    for (;;)
    {
        DWORD now = GetTickCount();
        if ((LONG)(end - now) <= 0) return;
        MsgWaitForMultipleObjects(0, NULL, FALSE, gl_dc && end - now > 16 ? 16 : end - now, QS_ALLINPUT);
        while (PeekMessageA(&msg, 0, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT) return;
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        if (gl_dc)
        {
            glClearColor(0.1f, 0.8f, 0.2f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            SwapBuffers(gl_dc);
        }
    }
}

static BOOL init_gl(HWND hwnd, BOOL second_context)
{
    PIXELFORMATDESCRIPTOR pfd = {sizeof(pfd), 1, PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
                                 PFD_TYPE_RGBA, 32};
    HDC dc = GetDC(hwnd);
    HGLRC ctx, ctx2;
    int format;

    if (!(format = ChoosePixelFormat(dc, &pfd)) || !SetPixelFormat(dc, format, &pfd) ||
        !(ctx = wglCreateContext(dc)) || !wglMakeCurrent(dc, ctx))
    {
        printf("child: OpenGL setup failed %lu\n", GetLastError());
        return FALSE;
    }
    if (second_context &&
        (!(ctx2 = wglCreateContext(dc)) || !wglMakeCurrent(dc, ctx2) || !wglMakeCurrent(dc, ctx)))
    {
        printf("child: OpenGL setup failed %lu\n", GetLastError());
        return FALSE;
    }
    gl_dc = dc;
    return TRUE;
}

static HWND find_child(HWND parent)
{
    return FindWindowExA(parent, NULL, "xprocchild_child", NULL);
}

static void log_phase(const char *name, HWND parent)
{
    HWND child = find_child(parent);
    RECT r = {0};

    if (child) GetWindowRect(child, &r);
    printf("%s child=%ld,%ld pid=%lu visible=%d\n", name, r.left, r.top, GetCurrentProcessId(),
           child && IsWindowVisible(child));
}

static int run_child(HWND parent, DWORD seconds, int gl, int splash)
{
    HWND hwnd;

    color = RGB(220, 30, 30);
    if (splash)
    {
        HWND popup = CreateWindowExA(0, "xprocchild_child", "xprocchild splash", WS_POPUP | WS_VISIBLE,
                                     900, 600, 200, 100, NULL, NULL, GetModuleHandleA(NULL), NULL);
        CreateWindowExA(0, "xprocchild_child", "xprocchild empty", WS_POPUP | WS_VISIBLE,
                        0, 0, 0, 0, NULL, NULL, GetModuleHandleA(NULL), NULL);
        pump(700);
        ShowWindow(popup, SW_HIDE);
    }
    hwnd = CreateWindowExA(0, "xprocchild_child", "xprocchild child", WS_OVERLAPPEDWINDOW,
                           200, 200, CHILD_W, CHILD_H, NULL, NULL, GetModuleHandleA(NULL), NULL);
    if (!hwnd) return 2;
    if (!SetParent(hwnd, parent)) { printf("child: SetParent failed %lu\n", GetLastError()); return 2; }
    MoveWindow(hwnd, CHILD_X, CHILD_Y, CHILD_W, CHILD_H, TRUE);
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    if (gl && !init_gl(hwnd, gl == 2)) return 2;
    pump(seconds * 1000);
    return 0;
}

int main(int argc, char **argv)
{
    char cmd[MAX_PATH + 64], exe[MAX_PATH];
    STARTUPINFOA si = {sizeof(si)};
    PROCESS_INFORMATION pi;
    DWORD seconds = 8;
    int gl, splash, hide;
    WNDCLASSA wc = {0};
    HWND hwnd;
    int i;

    setvbuf(stdout, NULL, _IONBF, 0);
    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_CROSS);
    wc.lpszClassName = "xprocchild_child";
    RegisterClassA(&wc);
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    wc.lpszClassName = "xprocchild_parent";
    RegisterClassA(&wc);

    gl = !strcmp(argv[argc - 1], "gl") ? 1 : !strcmp(argv[argc - 1], "gl2") ? 2 : 0;
    splash = !strcmp(argv[argc - 1], "splash");
    hide = !strcmp(argv[argc - 1], "hide");
    if (argc > 2 && !strcmp(argv[1], "child"))
        return run_child((HWND)(ULONG_PTR)strtoul(argv[2], NULL, 0), argc > 3 ? atoi(argv[3]) : seconds, gl, splash);
    if (argc > 1 && strncmp(argv[1], "gl", 2) && strcmp(argv[1], "splash") && strcmp(argv[1], "hide")) seconds = atoi(argv[1]);

    color = RGB(30, 60, 220);
    hwnd = CreateWindowExA(0, "xprocchild_parent", "xprocchild parent", WS_POPUP | WS_VISIBLE,
                           120, 140, PARENT_W, PARENT_H, NULL, NULL, wc.hInstance, NULL);
    UpdateWindow(hwnd);
    SetForegroundWindow(hwnd);
    if (hide)
    {
        pump(1000);
        puts("shown");
        ShowWindow(hwnd, SW_HIDE);
        puts("hidden");
        pump(seconds * 1000);
        DestroyWindow(hwnd);
        return 0;
    }

    GetModuleFileNameA(NULL, exe, sizeof(exe));
    sprintf(cmd, "\"%s\" child %#lx %lu%s", exe, (unsigned long)(ULONG_PTR)hwnd, seconds,
            gl == 2 ? " gl2" : gl ? " gl" : splash ? " splash" : "");
    if (!CreateProcessA(exe, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
    {
        printf("CreateProcess failed %lu\n", GetLastError());
        return 2;
    }

    for (i = 0; i < 50 && !find_child(hwnd); i++) pump(100);
    if (!find_child(hwnd)) { puts("child window never appeared: FAIL"); return 1; }
    pump(2000);
    log_phase("phase1", hwnd);

    pump(seconds * 250);
    SetWindowPos(hwnd, HWND_TOP, 120 + 60, 140 + 40, 0, 0, SWP_NOSIZE);
    SetForegroundWindow(hwnd);
    pump(1500);
    log_phase("phase2", hwnd);

    pump(seconds * 250);
    puts("done");
    DestroyWindow(hwnd);
    WaitForSingleObject(pi.hProcess, 5000);
    return 0;
}
