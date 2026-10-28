; Memory-only page 11h. Counts deliberately describe additional partitions;
; variants test structure/provenance without issuing any physical command.
native_partitions_reply proc near
        jmp short partitions_mock_validate
partitions_mock_bad:
        mov word ptr cs:[native_bad],1
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        ret
partitions_mock_validate:
        cmp byte ptr es:[bx+SRB_CDB+1],0
        jne partitions_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+3],0
        jne partitions_mock_bad
        cmp byte ptr es:[bx+SRB_CDB+5],0
        jne partitions_mock_bad
        push es
        push cs
        pop es
        mov di,offset native_mode
        xor al,al
        mov cx,64
        rep stosb
        pop es
        mov byte ptr cs:[native_mode],27
        mov byte ptr cs:[native_mode+3],8
        mov si,offset native_mode+12
        mov byte ptr cs:[si],11h
        mov byte ptr cs:[si+1],14
        mov byte ptr cs:[si+2],3
        mov byte ptr cs:[si+3],2
        mov byte ptr cs:[si+4],3Ch
        mov byte ptr cs:[si+5],3
        mov byte ptr cs:[si+6],18h
        mov cx,28
ifdef NATIVE_PARTITIONS_KIND
if NATIVE_PARTITIONS_KIND eq 1
        mov byte ptr cs:[si],91h ; PS is allowed
elseif NATIVE_PARTITIONS_KIND eq 2
        mov byte ptr cs:[si+2],0 ; pending/stale counts must not be normalized
        mov byte ptr cs:[si+3],255
elseif NATIVE_PARTITIONS_KIND eq 3
        mov byte ptr cs:[si+7],1
elseif NATIVE_PARTITIONS_KIND eq 4
        mov byte ptr cs:[si+1],13 ; odd descriptor byte
elseif NATIVE_PARTITIONS_KIND eq 5
        mov byte ptr cs:[native_mode+3],7
elseif NATIVE_PARTITIONS_KIND eq 6
        dec cx ; reported total exceeds actual bytes
elseif NATIVE_PARTITIONS_KIND eq 7
        mov byte ptr cs:[si],51h ; unsupported subpage form
elseif NATIVE_PARTITIONS_KIND eq 8
        mov byte ptr cs:[si],10h ; missing requested page
elseif NATIVE_PARTITIONS_KIND eq 9
        mov byte ptr cs:[si+1],6 ; duplicate target pages
        mov byte ptr cs:[si+8],11h
        mov byte ptr cs:[si+9],6
elseif NATIVE_PARTITIONS_KIND eq 10
        mov byte ptr cs:[native_mode],28 ; malformed trailing page header
        inc cx
elseif NATIVE_PARTITIONS_KIND eq 13
        mov byte ptr cs:[si+1],6 ; no size descriptors is valid
        mov byte ptr cs:[native_mode],19
        mov cx,20
endif
endif
        mov si,offset native_mode
        call native_copy
ifdef NATIVE_PARTITIONS_KIND
if NATIVE_PARTITIONS_KIND eq 11
        mov word ptr es:[bx+SRB_BufLen+2],1
elseif NATIVE_PARTITIONS_KIND eq 12
        and byte ptr es:[bx+SRB_Flags],not SRB_RESIDUAL
endif
endif
ifdef NATIVE_PARTITIONS_FAULT
        mov byte ptr es:[bx+SRB_Status],SS_ERR
        mov byte ptr es:[bx+SRB_TargStat],2
        mov byte ptr es:[bx+SRB_CDB+6],70h
        mov byte ptr es:[bx+SRB_CDB+6+7],6
        mov byte ptr es:[bx+SRB_CDB+6+2],3
if NATIVE_PARTITIONS_FAULT eq 1
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_PARTITIONS_FAULT eq 2
        mov byte ptr es:[bx+SRB_CDB+6+2],5
        mov byte ptr es:[bx+SRB_CDB+6+12],20h
elseif NATIVE_PARTITIONS_FAULT eq 3
        mov byte ptr es:[bx+SRB_CDB+6],71h
elseif NATIVE_PARTITIONS_FAULT eq 4
        mov byte ptr es:[bx+SRB_Status],SS_COMP
        mov byte ptr es:[bx+SRB_HaStat],11h
elseif NATIVE_PARTITIONS_FAULT eq 6
        mov byte ptr es:[bx+SRB_TargStat],8
elseif NATIVE_PARTITIONS_FAULT eq 7
        mov byte ptr es:[bx+SRB_CDB+6+2],80h
endif
endif
        ret
native_partitions_reply endp
