/* WoW64 regression test: Suspend/Get/SetThreadContext/Resume on a thread that keeps making syscalls.
 * Hook engines (e.g. the one in Adobe AIR 3.6) do this to every thread while patching code. If the 32-bit
 * context round-trip is wrong, the target thread resumes at a bogus Eip and crashes. */
#include <windows.h>
#include <stdio.h>

static volatile LONG stop, calls;
static unsigned char code[16];

static DWORD WINAPI worker(void *arg)
{
    while (!stop)
    {
        FlushInstructionCache(GetCurrentProcess(), code, sizeof(code));
        InterlockedIncrement(&calls);
    }
    return 0;
}

int main(int argc, char **argv)
{
    int i, rounds = argc > 1 ? atoi(argv[1]) : 20000, bad = 0;
    CONTEXT ctx;
    HANDLE t = CreateThread(NULL, 0, worker, NULL, 0, NULL);
    DWORD code_ = 0;

    for (i = 0; i < rounds; i++)
    {
        if (SuspendThread(t) == (DWORD)-1) { printf("SuspendThread failed %lu\n", GetLastError()); return 2; }
        ctx.ContextFlags = CONTEXT_FULL;
        if (!GetThreadContext(t, &ctx)) { printf("GetThreadContext failed %lu\n", GetLastError()); return 2; }
        if (ctx.SegCs != 0x23 && ctx.SegCs != 0x107 && !bad++) printf("round %d: unexpected SegCs %04lx Eip %08lx\n", i, ctx.SegCs, ctx.Eip);
        if (!SetThreadContext(t, &ctx)) { printf("SetThreadContext failed %lu\n", GetLastError()); return 2; }
        ResumeThread(t);
        if (GetExitCodeThread(t, &code_) && code_ != STILL_ACTIVE) break;
        if (!(i & 1023)) Sleep(0);
    }
    stop = 1;
    if (WaitForSingleObject(t, 5000)) { puts("worker hung: FAIL"); return 1; }
    GetExitCodeThread(t, &code_);
    printf("%d rounds, %ld syscalls, worker exit %lu: %s\n", i, calls, code_, code_ ? "FAIL" : "PASS");
    return code_ != 0;
}
