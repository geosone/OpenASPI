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

