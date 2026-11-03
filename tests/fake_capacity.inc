; READ CAPACITY, which every volume load sends first for the sector size: an
; uncounted answer with 512-byte blocks and a capacity (7FFFFFFFh sectors)
; that no test's volume reaches. Place first in a mock's far fake_aspi.
FAKE_CAPACITY macro
        local fake_not_capacity
        cmp byte ptr cs:[srb+SRB_CDB],25h
        jne fake_not_capacity
        push es
        push di
        les di,dword ptr cs:[srb+SRB_BufPointer]
        mov word ptr es:[di],0FF7Fh             ; last LBA 7FFFFFFEh
        mov word ptr es:[di+2],0FEFFh
        mov word ptr es:[di+4],0
        mov word ptr es:[di+6],0002h            ; block length 0200h
        pop di
        pop es
        mov byte ptr cs:[srb+SRB_Status],SS_COMP
        mov byte ptr cs:[srb+SRB_HaStat],0
        mov byte ptr cs:[srb+SRB_TargStat],0
        ret
fake_not_capacity:
endm
