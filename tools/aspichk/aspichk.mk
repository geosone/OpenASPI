# ASPICHK.EXE; included by the Makefile.  The host test is build/host/test_fatchk.

DOSASPICHK := $(BUILD)/dos/ASPICHK.EXE
ASPICHKOBJ := $(addprefix $(BUILD)/dos/aspichk/,aspichk.obj drive.obj fat_check.obj cptab.obj)
ASPICHKHDR := $(OPENFAT)/include/openfat/fat_check.h include/openaspi/types.h $(EXFATHDR)

$(BUILD)/dos/aspichk/%.obj: tools/aspichk/%.c tools/aspichk/drive.h $(ASPICHKHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<

$(BUILD)/dos/aspichk/fat_check.obj: $(OPENFAT)/src/fat/fat_check.c $(ASPICHKHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<

$(BUILD)/dos/aspichk/cptab.obj: common/cptab.c include/openaspi/cptab.h $(EXFATHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<

$(DOSASPICHK): $(ASPICHKOBJ) tools/aspichk/aspichk.mk
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ \
		$(foreach o,$(ASPICHKOBJ),file $(o)) \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=8192
