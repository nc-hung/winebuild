/* WoW64 regression test modelled on Adobe AIR 3.6's ATL-style window thunks:
 * carve 16-byte "mov [esp+4],imm32; jmp rel32" thunks out of one RWX page, FlushInstructionCache each one,
 * execute it, then write the next thunk into the same (already executed) page.
 * usage: flushic32 [rounds] [flush|noflush|yield|once]
 *   noflush: no syscall between write and execute; yield: SwitchToThread instead of FlushInstructionCache;
 *   once: only flush after the final write. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int __stdcall target(int a, int b) { return a + b; }

static void write_thunk(unsigned char *p, int value, void *dest)
{
    p[0] = 0xc7; p[1] = 0x44; p[2] = 0x24; p[3] = 0x04;         /* movl $value,4(%esp) */
    memcpy(p + 4, &value, 4);
    p[8] = 0xe9;                                                /* jmp dest */
    *(int *)(p + 9) = (int)((unsigned char *)dest - (p + 13));
}

int main(int argc, char **argv)
{
    int i, rounds = argc > 1 ? atoi(argv[1]) : 2000, fail = 0;
    const char *mode = argc > 2 ? argv[2] : "flush";
    unsigned char *page;

    setvbuf(stdout, NULL, _IONBF, 0);
    page = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);

    for (i = 0; i < rounds && !fail; i++)
    {
        unsigned char *p = page + 4096 - 16 * (1 + i % 256);    /* walk down the page like the SList pool */
        int (__stdcall *fn)(int, int) = (void *)p;

        if (i < 4 || !(i % 500)) printf("round %d\n", i);
        write_thunk(p, 0, NULL);                                 /* placeholder, like ATL's thunk init */
        if (!strcmp(mode, "flush") && !FlushInstructionCache(GetCurrentProcess(), p, 13)) fail = 1;
        if (!strcmp(mode, "yield")) SwitchToThread();
        write_thunk(p, i, target);
        if ((!strcmp(mode, "flush") || !strcmp(mode, "once")) && !FlushInstructionCache(GetCurrentProcess(), p, 13)) fail = 1;
        if (!strcmp(mode, "yield")) SwitchToThread();
        if (fn(1000, 7) != i + 7) { printf("round %d: thunk returned wrong value\n", i); fail = 1; }
    }
    printf("%d rounds: %s\n", i, fail ? "FAIL" : "PASS");
    return fail;
}
