/* Exercise 32-bit exception paths under WoW64: software raise, access violation, int3, int divide. */
#include <windows.h>
#include <stdio.h>
static volatile int hits;
static LONG CALLBACK veh(EXCEPTION_POINTERS *e)
{
    DWORD c = e->ExceptionRecord->ExceptionCode;
    hits++;
    printf("  caught %08lx at %p\n", c, e->ExceptionRecord->ExceptionAddress);
    if (c == 0xe0001234) return EXCEPTION_CONTINUE_EXECUTION;
    if (c == EXCEPTION_BREAKPOINT) { e->ContextRecord->Eip += 1; return EXCEPTION_CONTINUE_EXECUTION; }
    e->ContextRecord->Eip += (c == EXCEPTION_ACCESS_VIOLATION) ? 6 : 3;  /* skip faulting insn */
    return EXCEPTION_CONTINUE_EXECUTION;
}
int main(void)
{
    volatile int zero = 0, r = 0;
    AddVectoredExceptionHandler(1, veh);
    puts("raise"); fflush(stdout); RaiseException(0xe0001234, 0, 0, NULL);
    puts("access violation"); fflush(stdout);
    __asm__ volatile("movl $0, %%eax\n\t.byte 0xc7,0x00,0x01,0x00,0x00,0x00" ::: "eax", "memory"); /* movl $1,(%eax) = 6 bytes */
    puts("int3"); fflush(stdout); __asm__ volatile("int3");
    puts("divide"); fflush(stdout);
    __asm__ volatile("movl $1,%%eax\n\tcltd\n\tidivl %1" : "=a"(r) : "m"(zero) : "edx"); /* idiv m32 = 6 bytes? */
    printf("done, %d exceptions\n", hits);
    return 0;
}
