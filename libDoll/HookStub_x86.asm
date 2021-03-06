.model flat, C

; Machine code (functions) disguised as bytes
extern DollThreadIsCurrent:byte, DollHookGetCurrent:byte
extern DollOnHook:byte, DollOnAfterHook:byte, DollOnEPHook:byte

public HookStubBefore, HookStubA, HookStubB, HookStubOnDeny, HookStubEP
public HookStubBefore_len, HookStubBefore_HookOEPOffset, HookStubBefore_AddrOffset
public pushad_count

.code

; Machine's word size, in bytes
WORDSZ equ @WordSize

; Registers saved by the pushall macro, as a macro for usage in assembly code
; Currently: eax, ecx, edx, ebx, esp, ebp, esi, edi, eflags
PUSHAD_CNT equ 9

; pushall/popall macro saves/restores literally all general-purpose registers

pushall macro
    pushad
    pushfd
endm

; NOTE: popad will NOT restore esp's value from stack
; https://c9x.me/x86/html/file_module_x86_id_249.html
popall macro
    popfd
    popad
    mov esp, [esp - 4 * (PUSHAD_CNT - 4)] ; offset pushall::esp
endm

; Before: Each API keeps a copy, work as the "Detoured function"
; Purpose is to provide HookOEP
; Context (Before A):
;     stack == (return addr), (red zone...)
; Context (Before B):
;     stack == (red zone...)
; Context (Before OnDeny):
;     stack == (return addr), (red zone...)
HookStubBefore:
    push 0CCCCCCCCh ; HookOEP placeholder
    push 0CCCCCCCCh ; Address pointer placeholder
    ret
HookStubBefore_end:

; Side A: Standalone, called from HookStubBeforeA
;     Check if current thread a libDoll thread. If not so, save current context then hand execution over to C function
; Context:
;     stack == (HookOEP), (return addr), (red zone...)
HookStubA:
    pushall
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    lea eax, DollThreadIsCurrent
    call eax
    ;   DollThreadIsCurrent()
    ;   eax == ret
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    lea ecx, [esp + WORDSZ * PUSHAD_CNT]
    ;   ecx == &HookOEP
    test eax, eax
    jnz __HookStubA_isDoll
    ;   ecx == &HookOEP
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    push ecx
    lea eax, DollOnHook
    call eax
    add esp, WORDSZ
    ;   DollOnHook(&HookOEP)
    ;   stack == (pushall), (newOEP), (return addr), (red zone...)
    popall
    ;   stack == (newOEP), (return addr), (red zone...)
    ret
    ;   Hand control over to newOEP
    ;   stack == (return addr), (red zone...)

__HookStubA_isDoll:
    ;   ecx == &HookOEP
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    push ecx
    lea eax, DollHookGetCurrent
    call eax
    add esp, WORDSZ
    ;   DollHookGetCurrent(&HookOEP)
    ;   eax == &LIBDOLL_HOOK
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    mov edx, [eax + WORDSZ * 0] ; offset LIBDOLL_HOOK::pTrampoline
    ;   edx == pTrampoline
    mov [esp + WORDSZ * PUSHAD_CNT], edx
    ;   stack == (pushall), (pTrampoline), (return addr), (red zone...)
    popall
    ;   stack == (pTrampoline), (return addr), (red zone...)
    ret
    ;   Hand control over to pTrampoline
    ;   stack == (return addr), (red zone...)

; Side B: Standalone, called from HookStubBeforeB
;     Save current context then hand execution over to C function
; Context:
;     stack == (HookOEP), (red zone...)
HookStubB:
    pushall
    ;   stack == (pushall), (HookOEP), (red zone...)
    mov ecx, esp
    add ecx, WORDSZ * PUSHAD_CNT
    ;   ecx == &HookOEP
    ;   stack == (pushall), (HookOEP), (red zone...)
    push ecx
    lea eax, DollOnAfterHook
    call eax
    add esp, WORDSZ
    ;   DollOnAfterHook(&HookOEP)
    ;   stack == (pushall), (return addr), (red zone...)
    popall
    ;   stack == (return addr), (red zone...)
    ret
    ;   Hand control over to caller code
    ;   stack == (red zone...)

; Called in place of a denied procedure
; Context:
;     stack == (HookOEP), (return addr), (red zone...)
; NOTE: should act like a __nakedcall function, except that a stack balance will apply
; NOTE: Stack balance is happened in the "red zone"
HookStubOnDeny:
    pushall
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    lea ecx, [esp + WORDSZ * PUSHAD_CNT]
    ;   ecx == &HookOEP
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    push ecx
    lea eax, DollHookGetCurrent
    call eax
    add esp, WORDSZ
    ;   DollHookGetCurrent(&HookOEP)
    ;   eax == &LIBDOLL_HOOK
    ;   stack == (pushall), (HookOEP), (return addr), (red zone...)
    mov edx, [eax + WORDSZ * 1] ; offset LIBDOLL_HOOK::denySPOffset
    ;   edx == denySPOffset
    add [esp + WORDSZ * 4], edx ; offset pushad::esp
    ;   stack == (pushall with esp modified), (HookOEP), (return addr), (red zone...)
    lea ecx, [esp + WORDSZ * (PUSHAD_CNT + 1)] ; &(return addr)
    ;   ecx == &(return addr)
    mov esi, [ecx]
    ;   esi == return addr
    ;   Start to use edx already makes me feel pity, now here's another one... :(
    mov [ecx + edx], esi
    ; return addr sent to where it should be
    ;   stack == (pushall with esp modified), (HookOEP), (return addr), [stack balance area], (return addr), (red zone...)
    mov edx, [eax + WORDSZ * 2] ; offset LIBDOLL_HOOK::denyAX
    ;   edx == denyAX
    mov [esp + WORDSZ * 8], edx ; offset pushad::eax
    ;   stack == (pushall with esp & eax modified), (HookOEP), (return addr), [stack balance area], (return addr), (red zone...)
    popall
    ;   Magic happens since we modifyed esp
    ;   stack == (stack balance area the size of HookOEP), (return addr), (red zone...)
    lea esp, [esp + WORDSZ]
    ; lea instead of add to avoid flag corruption
    ;   stack == (return addr), (red zone...)
    ret
    ;   Hand control back to caller code
    ;   stack == (red zone...)

; Entry of EP hook: Standalone, called after DLL initialization
;     Save current context then hand execution over to C function
; Context:
;     stack == (red zone...)
HookStubEP:
    push eax
    ;   Reserve space for incoming jump address
    ;   stack == (return addr), (red zone...)
    pushall
    ;   stack == (pushall), (return addr), (red zone...)
    lea ecx, [esp + WORDSZ * PUSHAD_CNT]
    ;   ecx == &return addr
    ;   stack == (pushall), (return addr), (red zone...)
    push ecx
    lea eax, DollOnEPHook
    call eax
    add esp, WORDSZ
    ;   DollOnEPHook(&return addr)
    ;   stack == (pushall), (return addr), (red zone...)
    popall
    ;   stack == (return addr), (red zone...)
    ret
    ;   Hand control over to EP
    ;   stack == (red zone...)

.const

; Length of HookStubBefore*, used for copying & fill in HookOEP
HookStubBefore_len \
    dd HookStubBefore_end - HookStubBefore

; Offset to HookOEP placeholder
HookStubBefore_HookOEPOffset \
    dd 1

; Offset to address pointer placeholder
HookStubBefore_AddrOffset \
    dd 6

; Registers saved by the pushad/pushall instruction
pushad_count \
    dd PUSHAD_CNT

end