; Generic block IOCTL 40h updates logical device parameters, not media format.
; Candidate BPB and unit state are staged in resident scratch buffers. Validate
; packet length, geometry, FAT type and capacity before publishing the shadow:
; malformed input does not publish a candidate. A failed media preflight also
; invalidates cached MEDIA/override state. DS=CS; non-reentrant.
; See docs/block-parameters.md for DOS parameter layout and FAT32 gating.

; Generic IOCTL SET PARAMETERS (40h).
parameter_candidate db 7+BPB_STORE_SIZE dup (0)
parameter_shadow db UNIT_SIZE dup (0)
parameter_size dw BPB_SIZE

; condition is the SUCCESS branch (for example jbe after a bound check).
; If it is false, jump to failure with an unconditional near jump. This avoids
; out-of-range 8086 conditional jumps; it does not invert the preceding flags.
; NT_JUMP in the tape implementation uses the opposite convention: its
; condition is the branch that TAKES the failure/target path.
PB_CHECK macro condition, failure
        local okay
        condition okay
        jmp failure
okay:
endm

; Input: ES:BX DOS request, unit_ptr selects the live unit, DS=CS.
; Stage a bounded category-08h classic or category-48h extended BPB, synthesize
; a boot-sector envelope for common validation, then preflight physical bounds.
; Output: CF clear after publishing current/default BPB; CF set with AL error.
; No filesystem sectors are written. Scratch buffers and SRB are overwritten.
set_parameters proc near
        mov word ptr [parameter_size],BPB_SIZE
        mov ax,0FFE0h
        cmp byte ptr es:[bx+RH_IOCTL_CATEGORY],48h
        jne params_size_ready
        mov word ptr [parameter_size],BPB_STORE_SIZE
        mov ax,0FFC4h
params_size_ready:
        les bp,dword ptr es:[bx+RH_IOCTL_PARAM]
        cmp bp,ax
        PB_CHECK jbe,params_invalid
        mov ax,es
        or ax,bp
        PB_CHECK jnz,params_invalid
        mov al,byte ptr es:[bp]
        test al,0FAh                  ; BPB-only, no track-layout-only request
        PB_CHECK jz,params_invalid
        test al,4                     ; uniform 512-byte sectors required
        PB_CHECK jnz,params_invalid
        ; Capture only the bounded descriptor/BPB prefix, without caller writes.
        push ds
        push es
        pop ds
        push cs
        pop es
        mov si,bp
        mov di,offset parameter_candidate
        mov cx,word ptr cs:[parameter_size]
        add cx,7
        rep movsb
        pop ds
        mov di,offset sector_buf
        xor ax,ax
        mov cx,512
        rep stosb
        mov byte ptr [sector_buf],0EBh
        mov word ptr [sector_buf+510],0AA55h
        mov si,offset parameter_candidate+7
        mov di,offset sector_buf+0Bh
        mov cx,word ptr [parameter_size]
        rep movsb
        cmp word ptr [sector_buf+22],0
        jne params_classic
        cmp word ptr [parameter_size],BPB_STORE_SIZE
        PB_CHECK je,params_media_bad
        call check_boot_sector
        PB_CHECK jnc,params_media_bad
        jmp short params_bpb_valid
params_classic:
        call check_boot_sector
        PB_CHECK jnc,params_media_bad
        call validate_classic_parameters
        PB_CHECK jnc,params_media_bad
        ; FAT12/16 has no extended FAT32 BPB fields.
        mov di,offset parameter_candidate+7+BPB_SIZE
        mov cx,BPB_STORE_SIZE-BPB_SIZE
        xor ax,ax
        rep stosb
; The candidate has passed syntax/layout checks. Probe a COPY of the unit,
; so load_volume cannot accidentally install the medium's BPB over the live
; logical override. A probe failure still invalidates live cache flags below:
; old geometry must not remain usable after media identity becomes uncertain.
params_bpb_valid:
        call validate_parameter_descriptor
        PB_CHECK jnc,params_invalid
        ; Preflight against a shadow record: no candidate BPB becomes active
        ; before capacity, actual volume and all address bounds are checked.
        mov si,word ptr [unit_ptr]
        mov di,offset parameter_shadow
        mov cx,UNIT_SIZE
        rep movsb
        mov di,offset parameter_shadow
        call block_read_capacity
        PB_CHECK jnc,params_device_failed
        call load_volume
        PB_CHECK jnc,params_device_failed
        mov ax,word ptr [parameter_candidate+7+BPB_HIDDEN]
        cmp ax,word ptr [parameter_shadow+U_START]
        PB_CHECK je,params_range_bad
        mov ax,word ptr [parameter_candidate+7+BPB_HIDDEN+2]
        cmp ax,word ptr [parameter_shadow+U_START+2]
        PB_CHECK je,params_range_bad
        mov ax,word ptr [parameter_candidate+7+BPB_TOTAL16]
        xor dx,dx
        or ax,ax
        jnz params_total_ready
        mov ax,word ptr [parameter_candidate+7+BPB_TOTAL32]
        mov dx,word ptr [parameter_candidate+7+BPB_TOTAL32+2]
params_total_ready:
        mov bx,word ptr [volume_extent]
        or bx,word ptr [volume_extent+2]
        jz params_physical_bound
        cmp dx,word ptr [volume_extent+2]
        PB_CHECK jbe,params_range_bad
        jb params_physical_bound
        cmp ax,word ptr [volume_extent]
        PB_CHECK jbe,params_range_bad
params_physical_bound:
        add ax,word ptr [parameter_shadow+U_START]
        adc dx,word ptr [parameter_shadow+U_START+2]
        PB_CHECK jnc,params_range_bad
        cmp dx,word ptr [parameter_shadow+U_CAPACITY+2]
        PB_CHECK jbe,params_range_bad
        jb params_commit
        cmp ax,word ptr [parameter_shadow+U_CAPACITY]
        PB_CHECK jbe,params_range_bad
; Bit 0 selects current versus default parameters. Current updates publish
; U_START, MEDIA, FAT type and the explicit BPB override; default updates copy
; only U_DEFAULT_BPB. Device capacity and unrelated lock/access/session flags
; remain owned by their own paths, not by the candidate descriptor.
params_commit:
        mov di,word ptr [unit_ptr]
        test byte ptr [parameter_candidate],1
        jz params_default
        mov ax,word ptr [parameter_shadow+U_START]
        mov word ptr [di+U_START],ax
        mov ax,word ptr [parameter_shadow+U_START+2]
        mov word ptr [di+U_START+2],ax
        or byte ptr [di+U_FLAGS],UF_MEDIA or UF_BPB_OVERRIDE
        and byte ptr [di+U_FLAGS],not UF_FAT32
        cmp word ptr [parameter_candidate+7+BPB_FATSIZE],0
        jne params_current_copy
        or byte ptr [di+U_FLAGS],UF_FAT32
params_current_copy:
        add di,U_BPB
        jmp short params_copy
params_default:
        add di,U_DEFAULT_BPB
params_copy:
        mov si,offset parameter_candidate+7
        mov cx,BPB_STORE_SIZE
        rep movsb
        clc
        ret
params_invalid:
        mov al,ERR_UNKNOWN_CMD
        stc
        ret
params_media_bad:
        mov al,ERR_UNKNOWN_MEDIA
        stc
        ret
params_range_bad:
        mov al,ERR_UNKNOWN_MEDIA
params_device_failed:
        ; A failed media preflight must not leave a stale override usable.
        mov di,word ptr [unit_ptr]
        and byte ptr [di+U_FLAGS],not (UF_MEDIA or UF_BPB_OVERRIDE)
        stc
        ret
set_parameters endp

; Descriptor fields must continue to describe this device. Geometry is a
; logical translation, checked with the same round-up rule as GET 60h.
validate_parameter_descriptor proc near
        mov di,word ptr [unit_ptr]
        mov ax,1
        mov dl,5
        test byte ptr [di+U_FLAGS],UF_REMOVABLE
        jz params_descriptor_class
        xor ax,ax
        mov dl,7
params_descriptor_class:
        cmp word ptr [parameter_candidate+2],ax
        PB_CHECK je,params_descriptor_bad
        cmp byte ptr [parameter_candidate+1],dl
        PB_CHECK je,params_descriptor_bad
        cmp byte ptr [parameter_candidate+6],0
        PB_CHECK je,params_descriptor_bad
        mov ax,word ptr [parameter_candidate+7+BPB_HEADS]
        or ax,ax
        PB_CHECK jnz,params_descriptor_bad
        cmp ax,256
        PB_CHECK jbe,params_descriptor_bad
        mov cx,word ptr [parameter_candidate+7+BPB_SPT]
        or cx,cx
        PB_CHECK jnz,params_descriptor_bad
        cmp cx,63
        PB_CHECK jbe,params_descriptor_bad
        mul cx
        mov cx,ax
        mov ax,word ptr [parameter_candidate+7+BPB_TOTAL16]
        xor dx,dx
        or ax,ax
        jnz params_geometry_total
        mov ax,word ptr [parameter_candidate+7+BPB_TOTAL32]
        mov dx,word ptr [parameter_candidate+7+BPB_TOTAL32+2]
; Descriptor cylinders must cover hidden+volume sectors, rounded upward by
; heads*sectors_per_track. Check DX<divisor before 16-bit DIV: otherwise a
; valid-looking large geometry could trap instead of returning a DOS error.
params_geometry_total:
        add ax,word ptr [parameter_candidate+7+BPB_HIDDEN]
        adc dx,word ptr [parameter_candidate+7+BPB_HIDDEN+2]
        PB_CHECK jnc,params_descriptor_bad
        cmp dx,cx
        PB_CHECK jb,params_descriptor_bad
        div cx
        or dx,dx
        jz params_geometry_cylinders
        inc ax
        PB_CHECK jnz,params_descriptor_bad
params_geometry_cylinders:
        cmp ax,word ptr [parameter_candidate+4]
        PB_CHECK je,params_descriptor_bad
        clc
        ret
params_descriptor_bad:
        stc
        ret
validate_parameter_descriptor endp

; Full FAT12/16 layout validation for new BPBs. Leaves DI/BP intact.
validate_classic_parameters proc near
        cmp word ptr [sector_buf+14],0
        PB_CHECK jne,params_classic_bad
        cmp word ptr [sector_buf+17],0
        PB_CHECK jne,params_classic_bad
        cmp byte ptr [sector_buf+16],2
        PB_CHECK jbe,params_classic_bad
        mov bx,word ptr [sector_buf+19]
        xor dx,dx
        or bx,bx
        jz params_classic_large
        mov ax,word ptr [sector_buf+32]
        or ax,word ptr [sector_buf+34]
        PB_CHECK jz,params_classic_bad
        jmp short params_classic_total
params_classic_large:
        mov bx,word ptr [sector_buf+32]
        mov dx,word ptr [sector_buf+34]
params_classic_total:
        sub bx,word ptr [sector_buf+14]
        sbb dx,0
        PB_CHECK jnc,params_classic_bad
        xor ax,ax
        mov al,byte ptr [sector_buf+16]
        mov si,ax
params_classic_fats:
        sub bx,word ptr [sector_buf+22]
        sbb dx,0
        PB_CHECK jnc,params_classic_bad
        dec si
        jnz params_classic_fats
        mov ax,word ptr [sector_buf+17]
        dec ax
        mov cl,4
        shr ax,cl
        inc ax
        sub bx,ax
        sbb dx,0
        PB_CHECK jnc,params_classic_bad
        mov cl,byte ptr [sector_buf+13]
params_classic_clusters:
        cmp cl,1
        jbe params_classic_count
        shr dx,1
        rcr bx,1
        shr cl,1
        jmp short params_classic_clusters
; Data sectors divided by sectors/cluster determine FAT12 versus FAT16.
; The FAT must hold cluster_count+2 entries. Compare bytes without truncating:
; FAT16 needs 2 bytes/entry; FAT12 compares 3*(entries) against 1024*FAT_sectors,
; equivalent to checking packed 12-bit entries against 512-byte sectors.
params_classic_count:
        or dx,dx
        PB_CHECK jz,params_classic_bad
        or bx,bx
        PB_CHECK jnz,params_classic_bad
        cmp bx,65525
        PB_CHECK jb,params_classic_bad
        mov cx,2
        mov si,512
        cmp bx,4085
        jae params_classic_entries
        mov cx,3                      ; FAT12: 3 bytes hold two entries
        mov si,1024
params_classic_entries:
        mov ax,bx
        add ax,2
        mul cx
        mov cx,dx
        mov bx,ax
        mov ax,word ptr [sector_buf+22]
        mul si
        cmp dx,cx
        PB_CHECK jae,params_classic_bad
        ja params_classic_ok
        cmp ax,bx
        PB_CHECK jae,params_classic_bad
params_classic_ok:
        clc
        ret
params_classic_bad:
        stc
        ret
validate_classic_parameters endp
