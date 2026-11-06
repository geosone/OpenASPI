# EXCHK.EXE and its host test; included by the Makefile.

DOSEXCHK := $(BUILD)/dos/EXCHK.EXE
EXCHKWCC := $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -iinclude -i$(OPENFAT)/include -i$(WATCOM)/h
EXCHKOBJ := $(addprefix $(BUILD)/dos/exchk/,exchk.obj exfat_check.obj exfat.obj codepage.obj name83.obj)

$(BUILD)/dos/exchk/exchk.obj: tools/exchk/exchk.c $(EXFATHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<

$(BUILD)/dos/exchk/%.obj: $(OPENFAT)/src/exfat/%.c $(EXFATHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<
$(BUILD)/dos/exchk/%.obj: $(OPENFAT)/src/%.c $(EXFATHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<

$(DOSEXCHK): $(EXCHKOBJ) tools/exchk/exchk.mk
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ \
		$(foreach o,$(EXCHKOBJ),file $(o)) \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=8192
