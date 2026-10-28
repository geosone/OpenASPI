# EXFMT.EXE; included by the Makefile.

DOSEXFMT := $(BUILD)/dos/EXFMT.EXE
EXFMTWCC := $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -iinclude -i$(WATCOM)/h
EXFMTOBJ := $(addprefix $(BUILD)/dos/exfmt/,exfmt.obj exfat_format.obj upcase.obj codepage.obj)

$(BUILD)/dos/exfmt/exfmt.obj: tools/exfmt/exfmt.c $(EXFATHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXFMTWCC) -fo=$@ $<

$(BUILD)/dos/exfmt/%.obj: common/exfat/%.c $(EXFATHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXFMTWCC) -fo=$@ $<

$(DOSEXFMT): $(EXFMTOBJ) tools/exfmt/exfmt.mk
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ \
		$(foreach o,$(EXFMTOBJ),file $(o)) \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=8192
