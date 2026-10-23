; 16-bit large-model C ABI boundary. entry and request are FAR pointers;
; push the SRB segment then offset for the manager call, then remove both words.
; Preserve C-visible register/segment state even if a third-party manager does
; not. This bridge submits only; main.c waits until SRB storage can be reused.

; C bridge: preserve registers around third-party DOS ASPI entry points.
        .8086
        .model large, c
        .code
        public aspi_submit
aspi_submit proc far uses bx cx dx si di ds es, entry:dword, request:dword
        push word ptr request+2
        push word ptr request
        call dword ptr entry
        add sp, 4
        ret
aspi_submit endp
        end

