/* Rosetta/WoW64 probe: after a 32-bit write into an already-executed code page, does a far transfer to the 64-bit
 * code segment really switch to 64-bit mode? Wine's syscall thunk uses "ljmp *m16:32"; this compares variants.
 * The 64-bit snippet is "xor eax,eax; rex nop", which leaves eax=1 instead of 0 if it runs as 32-bit code.
 * back32 likewise sets bit 4 of eax only when it runs as 32-bit code (it would crash on "ret" as 64-bit code).
 * usage: farjmp32 [rounds] [ljmp|lret|direct|lcall] [smc|nosmc|smc64|smc64code|smc64fresh] [ljmp|lretq|iretq]
 *   smc: the 32-bit loop rewrites a thunk each round; smc64*: the 64-bit snippet writes a byte into the thunk page,
 *   its own code page or a page nobody executed; the last argument picks how the snippet returns to 32-bit code. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int __stdcall target(int a, int b) { return a + b; }

static void write_thunk(unsigned char *p, int value, void *dest)
{
    p[0] = 0xc7; p[1] = 0x44; p[2] = 0x24; p[3] = 0x04;
    memcpy(p + 4, &value, 4);
    p[8] = 0xe9;
    *(int *)(p + 9) = (int)((unsigned char *)dest - (p + 13));
}

static unsigned char *put(unsigned char *p, const void *bytes, int len) { memcpy(p, bytes, len); return p + len; }
static unsigned char *put32(unsigned char *p, DWORD v) { return put(p, &v, 4); }
static unsigned char *put16(unsigned char *p, WORD v) { return put(p, &v, 2); }

int main(int argc, char **argv)
{
    int i, rounds = argc > 1 ? atoi(argv[1]) : 2000, bad = 0, res;
    const char *how = argc > 2 ? argv[2] : "ljmp";
    const char *where = argc > 3 ? argv[3] : "smc";
    const char *ret = argc > 4 ? argv[4] : "ljmp";
    BOOL smc = !strcmp(where, "smc"), smc64 = !strncmp(where, "smc64", 5);
    unsigned char *fresh = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    WORD ss32;
    unsigned char *code = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    unsigned char *thunks = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    unsigned char *tramp = code, *back32 = code + 0x40, *snip64 = code + 0x80, *fp64 = code + 0xc0, *fp32 = code + 0xd0;
    unsigned char *p;
    unsigned char *poke = !strcmp(where, "smc64code") ? code + 0xff0 : !strcmp(where, "smc64fresh") ? fresh : thunks + 4095;
    WORD cs32, cs64 = 0x2b;
    int (*fn)(void) = (void *)tramp;

    setvbuf(stdout, NULL, _IONBF, 0);
    __asm__ volatile ("movw %%cs,%0; movw %%ss,%1" : "=r"(cs32), "=r"(ss32));
    memset(code, 0xcc, 4096);

    p = tramp;
    if (!strcmp(how, "lret"))
    {
        p = put(p, "\x68", 1); p = put32(p, cs64);                  /* push $cs64 */
        p = put(p, "\x68", 1); p = put32(p, (DWORD)snip64);         /* push $snip64 */
        p = put(p, "\xcb", 1);                                      /* lret */
    }
    else if (!strcmp(how, "direct"))
    {
        p = put(p, "\xea", 1); p = put32(p, (DWORD)snip64); p = put16(p, cs64);   /* ljmp $cs64,$snip64 */
    }
    else if (!strcmp(how, "lcall"))
    {
        p = put(p, "\xff\x1d", 2); p = put32(p, (DWORD)fp64);        /* lcall *fp64 */
        p = put(p, "\xc3", 1);                                       /* ret */
    }
    else
    {
        p = put(p, "\xff\x2d", 2); p = put32(p, (DWORD)fp64);        /* ljmp *fp64 */
    }
    put(back32, "\x31\xc9\x41\x90\xc1\xe1\x04\x09\xc8\xc3", 10);   /* ecx = 1 (32-bit) or 0; eax |= ecx << 4; ret */

    p = put(snip64, "\x31\xc0\x40\x90", 4);                          /* xor eax,eax; rex nop | inc eax; nop */
    if (smc64) { p = put(p, "\x88\x04\x25", 3); p = put32(p, (DWORD)poke); }   /* mov %al,poke */
    if (!strcmp(how, "lcall")) put(p, "\xcb", 1);                    /* lret back to the caller */
    else if (!strcmp(ret, "lretq"))
    {
        p = put(p, "\x68", 1); p = put32(p, cs32);                  /* pushq $cs32 */
        p = put(p, "\x68", 1); p = put32(p, (DWORD)back32);         /* pushq $back32 */
        put(p, "\x48\xcb", 2);                                      /* lretq */
    }
    else if (!strcmp(ret, "iretq"))
    {
        p = put(p, "\x49\x89\xe0", 3);                              /* mov %rsp,%r8 */
        p = put(p, "\x68", 1); p = put32(p, ss32);                  /* pushq $ss32 */
        p = put(p, "\x41\x50\x9c", 3);                              /* pushq %r8; pushfq */
        p = put(p, "\x68", 1); p = put32(p, cs32);                  /* pushq $cs32 */
        p = put(p, "\x68", 1); p = put32(p, (DWORD)back32);         /* pushq $back32 */
        put(p, "\x48\xcf", 2);                                      /* iretq */
    }
    else { p = put(p, "\xff\x2c\x25", 3); put32(p, (DWORD)fp32); }   /* ljmp *fp32 */
    put16(put32(fp64, (DWORD)snip64), cs64);
    put16(put32(fp32, (DWORD)back32), cs32);
    FlushInstructionCache(GetCurrentProcess(), code, 4096);

    printf("cs32=%04x cs64=%04x via %s, %s, back via %s\n", cs32, cs64, how, where, ret);
    for (i = 0; i < rounds && bad < 5; i++)
    {
        unsigned char *t = thunks + 4096 - 16 * (1 + (smc ? i % 256 : 0));
        int (__stdcall *thunk)(int, int) = (void *)t;

        if (smc || i == 0) write_thunk(t, i, target);
        res = fn();
        if (res & 1) { printf("round %d: 64-bit snippet ran in 32-bit mode\n", i); bad++; }
        if (!(res & 16)) { printf("round %d: return to 32-bit code ran in 64-bit mode\n", i); bad++; }
        if (thunk(1000, 7) != (smc ? i : 0) + 7) { printf("round %d: thunk returned wrong value\n", i); bad++; }
    }
    printf("%d rounds, %d bad: %s\n", i, bad, bad ? "FAIL" : "PASS");
    return !!bad;
}
