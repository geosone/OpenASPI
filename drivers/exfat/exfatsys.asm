; EXFAT.SYS: the DOS side of the exFAT redirector.
;
; Device header, strategy and interrupt routines, the INT 2Fh (AH=11h,
; network redirector) and INT 21h hooks, and BIOS/DOS calls for the C part
; (exfatsys.c).  All code and data are in one group, so CS = DS = SS while C
; runs on the driver's own stack.
;
;   DEVICE=C:\DOS\EXFAT.SYS [/L:x] [/Q]
;
; Copyright (C) 2026 GeosOne.  GNU General Public License version 3.

        .8086
        option casemap:none

_HDR    segment para public 'CODE'
_HDR    ends
_TEXT   segment word public 'CODE'
_TEXT   ends
CONST   segment word public 'DATA'
CONST   ends
CONST2  segment word public 'DATA'
CONST2  ends
_DATA   segment word public 'DATA'
_DATA   ends
_BSS    segment word public 'BSS'
_BSS    ends
_STK    segment word public 'STK'
_STK    ends
INIT_TEXT segment byte public 'INIT'
INIT_TEXT ends
INIT_DATA segment word public 'INIT'
INIT_DATA ends
DGROUP  group _HDR, _TEXT, CONST, CONST2, _DATA, _BSS, _STK, INIT_TEXT, INIT_DATA

        public  _int13, _int21, _int1a, _old2f, _old21, _bss_start, _resident_end
        public  _svc_call, _aspi_callback_off

        extern  _redir:near, _drv_init:near, _assign:near, _aspi_notify:near
ifdef EXFAT_LFN
        extern  _lfn:near
endif
        extern  _exfat_info:near

STACKSIZE equ   1024
LFNSTACK equ    1024                    ; the 71xxh calls, which call DOS

_HDR    segment
        assume  cs:DGROUP, ds:DGROUP
        dd      -1
        dw      8000h                   ; character device
        dw      offset DGROUP:strategy
        dw      offset DGROUP:interrupt
        db      '$EXFAT$ '
        db      'EXI1'                  ; the volumes for the tools
        dw      offset DGROUP:_exfat_info

req     dd      0
_old2f  dd      0
_old21  dd      0
save_ss dw      0
save_sp dw      0
save_ax dw      0
result  dw      0
busy    db      0

strategy proc far
        mov     word ptr cs:req, bx
        mov     word ptr cs:req+2, es
        ret
strategy endp

; INIT only; the redirector does not take device requests.
interrupt proc far
        push    ax
        push    bx
        push    es
        les     bx, cs:req
        mov     word ptr es:[bx+3], 8103h      ; error, unknown command
        cmp     byte ptr es:[bx+2], 0
        jne     int_done
        mov     ax, offset DGROUP:_drv_init
        call    on_stack
int_done:
        pop     es
        pop     bx
        pop     ax
        ret
interrupt endp

; Calls the C function at AX with the device request on the own stack:
; int __cdecl f(void __far *req).  All registers are kept.
on_stack proc near
        mov     cs:save_ax, ax
        mov     cs:save_ss, ss
        mov     cs:save_sp, sp
        mov     ax, cs
        cli
        mov     ss, ax
        mov     sp, offset DGROUP:stack_top
        sti
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     ds, ax
        mov     es, ax
        cld
        push    word ptr cs:req+2
        push    word ptr cs:req
        call    cs:save_ax
        add     sp, 4
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        cli
        mov     ss, cs:save_ss
        mov     sp, cs:save_sp
        sti
        ret
on_stack endp

; INT 2Fh: AH=11h goes to the C dispatcher with the registers in a struct
; (struct regs in exfatsys.c); it returns 0 when handled, else the call is
; chained.  The carry flag of the struct goes back to the caller.
int2f   proc far
        cmp     ah, 11h
        je      @F
to_chain:
        jmp     cs:_old2f
@@:     cmp     cs:busy, 0
        jne     to_chain
        mov     cs:busy, 1
        mov     cs:save_ax, ax
        mov     cs:save_ss, ss
        mov     cs:save_sp, sp
        mov     ax, cs
        cli
        mov     ss, ax
        mov     sp, offset DGROUP:stack_top
        sti
        push    ax                      ; flags (out)
        push    cs:save_ss
        push    cs:save_sp
        push    cs:save_ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     ds, ax
        mov     es, ax
        cld
        mov     ax, sp
        push    ax
        call    _redir
        add     sp, 2
        mov     result, ax
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        add     sp, 4
        pop     cs:save_ax              ; flags (out)
        cli
        mov     ss, cs:save_ss
        mov     sp, cs:save_sp
        sti
        mov     cs:busy, 0
        cmp     cs:result, 0
        jne     chain_restore
        push    bp
        mov     bp, sp
        and     word ptr [bp+6], not 1
        test    cs:save_ax, 1
        jz      @F
        or      word ptr [bp+6], 1
@@:     pop     bp
        iret
chain_restore:
        ; not ours: the registers are as the caller gave them
        jmp     cs:_old2f
int2f   endp

; INT 21h: the drive letters are taken when the first program is started
; (AH=4Bh), as the DOS drive table (CDS) exists only after CONFIG.SYS.
; AH=71h (long file names) goes to the C function lfn, as INT 2Fh to redir,
; but on a stack of its own: lfn calls DOS, and DOS the redirector.
int21   proc far
ifdef EXFAT_LFN
        cmp     ah, 71h
        je      lfn21
endif
        cmp     ah, 4Bh
        jne     chain21
        cmp     cs:assigned, 0
        jne     chain21
        cmp     cs:busy, 0
        jne     chain21
        mov     cs:assigned, 1
        mov     cs:busy, 1
        push    ax
        mov     ax, offset DGROUP:_assign
        call    on_stack
        pop     ax
        mov     cs:busy, 0
chain21:
        jmp     cs:_old21
ifdef EXFAT_LFN
lfn21:  cmp     cs:lfn_busy, 0
        jne     chain21
        mov     cs:lfn_busy, 1
        mov     cs:lfn_ax, ax
        mov     cs:lfn_ss, ss
        mov     cs:lfn_sp, sp
        mov     ax, cs
        cli
        mov     ss, ax
        mov     sp, offset DGROUP:lfn_top
        sti
        push    ax                      ; flags (out)
        push    cs:lfn_ss
        push    cs:lfn_sp
        push    cs:lfn_ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     ds, ax
        mov     es, ax
        cld
        mov     ax, sp
        push    ax
        call    _lfn
        add     sp, 2
        mov     lfn_result, ax
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        add     sp, 4
        pop     cs:lfn_ax               ; flags (out)
        cli
        mov     ss, cs:lfn_ss
        mov     sp, cs:lfn_sp
        sti
        mov     cs:lfn_busy, 0
        cmp     cs:lfn_result, 0
        jne     lfn_chain
        push    bp
        mov     bp, sp
        and     word ptr [bp+6], not 1
        test    cs:lfn_ax, 1
        jz      @F
        or      word ptr [bp+6], 1
@@:     pop     bp
        iret
lfn_chain:
        ; not ours: the registers are as the caller gave them
        jmp     cs:_old21
lfn_busy db     0
lfn_ss  dw      0
lfn_sp  dw      0
lfn_ax  dw      0
lfn_result dw   0
endif
assigned db     0
int21   endp

; int __cdecl int13(struct iregs *), int21(struct iregs *) and
; int1a(struct iregs *): AX BX CX DX SI DI DS ES in and out; returns the
; carry flag.
iregs   struc
r_ax    dw      ?
r_bx    dw      ?
r_cx    dw      ?
r_dx    dw      ?
r_si    dw      ?
r_di    dw      ?
r_ds    dw      ?
r_es    dw      ?
iregs   ends

_int13  proc near
        mov     cs:intno, 13h
        jmp     short do_int
_int13  endp
_int1a  proc near
        mov     cs:intno, 1Ah
        jmp     short do_int
_int1a  endp
_int21  proc near
        mov     cs:intno, 21h
_int21  endp
do_int  proc near
        push    bp
        mov     bp, sp
        push    si
        push    di
        push    ds
        push    es
        mov     bx, [bp+4]
        push    bx
        mov     ax, [bx].iregs.r_ax
        mov     cx, [bx].iregs.r_cx
        mov     dx, [bx].iregs.r_dx
        mov     si, [bx].iregs.r_si
        mov     di, [bx].iregs.r_di
        mov     es, [bx].iregs.r_es
        push    [bx].iregs.r_ds
        mov     bx, [bx].iregs.r_bx
        pop     ds
        cmp     cs:intno, 13h
        jne     @F
        int     13h
        jmp     short int_ret
@@:     cmp     cs:intno, 1Ah
        jne     @F
        int     1Ah
        jmp     short int_ret
@@:     int     21h
int_ret:
        push    ds
        push    bx
        mov     bx, cs
        mov     ds, bx
        mov     bx, [bp-10]             ; the struct
        pop     [bx].iregs.r_bx
        pop     [bx].iregs.r_ds
        mov     [bx].iregs.r_ax, ax
        mov     [bx].iregs.r_cx, cx
        mov     [bx].iregs.r_dx, dx
        mov     [bx].iregs.r_si, si
        mov     [bx].iregs.r_di, di
        mov     [bx].iregs.r_es, es
        mov     ax, 0
        adc     ax, 0
        pop     bx
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     bp
        ret
intno   db      0
do_int  endp

; int __cdecl svc_call(unsigned off, unsigned seg, void *packet): the
; exFAT service of ASPIDSK/ASPIFDD (common/dos/exfat_svc.inc), ES:BX ->
; packet; returns the packet status.
_svc_call proc near
        push    bp
        mov     bp, sp
        push    si
        push    di
        push    es
        mov     ax, [bp+4]
        mov     word ptr svc_entry, ax
        mov     ax, [bp+6]
        mov     word ptr svc_entry+2, ax
        push    ds
        pop     es
        mov     bx, [bp+8]
        push    bx
        call    dword ptr svc_entry
        pop     bx
        mov     ax, [bx+2]
        pop     es
        pop     di
        pop     si
        pop     bp
        ret
svc_entry dd    0
_aspi_callback_off dw offset DGROUP:aspi_callback
_svc_call endp

; Far callback for ASPIDSK/ASPIFDD: BUILD BPB found a new exFAT medium,
; AL = unit, DX = the driver's segment.  Runs inside DOS on the block
; driver's stack: to aspi_notify(unit, seg) on the own stack, unless the
; driver is busy (then the medium is found at the next media check).
aspi_callback proc far
        cmp     cs:busy, 0
        jne     cb_done
        mov     cs:busy, 1
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     cs:save_ss, ss
        mov     cs:save_sp, sp
        mov     bx, cs
        cli
        mov     ss, bx
        mov     sp, offset DGROUP:stack_top
        sti
        mov     ds, bx
        mov     es, bx
        cld
        xor     ah, ah
        push    dx
        push    ax
        call    _aspi_notify
        add     sp, 4
        cli
        mov     ss, cs:save_ss
        mov     sp, cs:save_sp
        sti
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        mov     cs:busy, 0
cb_done:
        ret
aspi_callback endp

        public  _hook
; void __cdecl hook(void): INT 2Fh and INT 21h to the driver.
_hook   proc near
        push    es
        mov     ax, 352Fh
        int     21h
        mov     word ptr _old2f, bx
        mov     word ptr _old2f+2, es
        mov     ax, 3521h
        int     21h
        mov     word ptr _old21, bx
        mov     word ptr _old21+2, es
        mov     dx, offset DGROUP:int2f
        mov     ax, 252Fh
        int     21h
        mov     dx, offset DGROUP:int21
        mov     ax, 2521h
        int     21h
        pop     es
        ret
_hook   endp
_HDR    ends

_BSS    segment
_bss_start label byte
_BSS    ends

_STK    segment
ifdef EXFAT_LFN
        db      LFNSTACK dup (?)        ; first: INIT clears up to the main stack
lfn_top label   word
endif
        db      STACKSIZE dup (?)
stack_top label word
_resident_end label byte
_STK    ends

        end
