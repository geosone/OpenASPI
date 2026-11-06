# DEFRAG.EXE and its host test; included by the Makefile.

DEFRAGTESTBIN := $(BUILD)/host/test_defrag

DOSDEFRAG := $(BUILD)/dos/DEFRAG.EXE
DEFRAGOBJ := $(addprefix $(BUILD)/dos/defrag/,defrag.obj fat_defrag.obj) \
	$(addprefix $(BUILD)/dos/aspichk/,drive.obj fat_check.obj codepage.obj)

$(BUILD)/dos/defrag/defrag.obj: tools/defrag/defrag.c tools/aspichk/drive.h $(OPENFAT)/include/openfat/fat_defrag.h $(ASPICHKHDR)
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<

$(BUILD)/dos/defrag/fat_defrag.obj: $(OPENFAT)/src/fat/fat_defrag.c $(OPENFAT)/include/openfat/fat_defrag.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(EXCHKWCC) -fo=$@ $<

$(DOSDEFRAG): $(DEFRAGOBJ) tools/defrag/defrag.mk
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ \
		$(foreach o,$(DEFRAGOBJ),file $(o)) \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=8192
