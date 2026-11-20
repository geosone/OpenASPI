# NTFS.SYS (read-only NTFS drives) and the NTFS host test; included by the
# Makefile.  The assembler frame is EXFAT.SYS's (exfatsys.asm, NTFS_SYS).

DOSNTFS := $(BUILD)/dos/NTFS.SYS
# the same driver with the long file names (INT 21h AX=71xxh)
DOSNTFSL := $(BUILD)/dos/NTFSL.SYS
NTFSHDR := $(OPENFILESYSTEM)/include/openfat/ntfs.h include/openaspi/exfatsys.h include/openaspi/types.h
NTFSOBJ := $(BUILD)/dos/ntfssys_a.obj $(BUILD)/dos/ntfssys.obj $(BUILD)/dos/ntfs.obj $(BUILD)/dos/name83.obj $(BUILD)/dos/latin.obj $(BUILD)/dos/cpinit.obj
NTFSLOBJ := $(BUILD)/dos/ntfssysl_a.obj $(BUILD)/dos/ntfssysl.obj $(BUILD)/dos/ntfs.obj $(BUILD)/dos/name83.obj $(BUILD)/dos/latin.obj $(BUILD)/dos/cpinit.obj

$(BUILD)/dos/ntfssys_a.obj: drivers/exfat/exfatsys.asm | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -omf -0 -W4 -WX -DNTFS_SYS -Fo=$@ $<

$(BUILD)/dos/ntfssys.obj: drivers/ntfs/ntfssys.c $(NTFSHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

$(BUILD)/dos/ntfssysl_a.obj: drivers/exfat/exfatsys.asm | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -omf -0 -W4 -WX -DNTFS_SYS -DEXFAT_LFN -Fo=$@ $<

$(BUILD)/dos/ntfssysl.obj: drivers/ntfs/ntfssys.c $(NTFSHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -dNTFS_LFN -fo=$@ $<

$(BUILD)/dos/ntfs.obj: $(OPENFILESYSTEM)/src/ntfs/ntfs.c $(NTFSHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

$(DOSNTFS): $(NTFSOBJ) drivers/ntfs/ntfs.mk
	$(WLINK) format raw bin option offset=0,quiet,nodefaultlibs,map=$(BUILD)/dos/NTFS.map disable 1014,1023 \
		order clname CODE segment _HDR segment _TEXT clname DATA clname BSS clname STK clname INIT \
		$(foreach o,$(NTFSOBJ),file $(o)) library $(WATCOM)/lib286/dos/clibs.lib name $@

$(DOSNTFSL): $(NTFSLOBJ) drivers/ntfs/ntfs.mk
	$(WLINK) format raw bin option offset=0,quiet,nodefaultlibs,map=$(BUILD)/dos/NTFSL.map disable 1014,1023 \
		order clname CODE segment _HDR segment _TEXT clname DATA clname BSS clname STK clname INIT \
		$(foreach o,$(NTFSLOBJ),file $(o)) library $(WATCOM)/lib286/dos/clibs.lib name $@
