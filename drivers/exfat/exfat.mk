# EXFAT.SYS and the exFAT host test; included by the Makefile.

DOSEXFAT := $(BUILD)/dos/EXFAT.SYS
EXFATTESTBIN := $(BUILD)/host/test_exfat
EXFATCORE := common/exfat/exfat.c common/exfat/codepage.c
EXFATHDR := include/openaspi/exfat.h include/openaspi/types.h
EXFATOBJ := $(BUILD)/dos/exfatsys_a.obj $(BUILD)/dos/exfatsys.obj $(BUILD)/dos/exfat.obj $(BUILD)/dos/codepage.obj
# small model, no stack checks, no C runtime start-up: CS = DS = SS
EXFATWCC := $(WCC) -q -ms -0 -os -s -zl -zdp -wx -we -Iinclude -I$(WATCOM)/h

$(EXFATTESTBIN): tests/exfat_test.c $(EXFATCORE) $(EXFATHDR)
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/exfat_test.c $(EXFATCORE)

$(BUILD)/dos/exfatsys_a.obj: drivers/exfat/exfatsys.asm | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -omf -0 -W4 -WX -Fo=$@ $<

$(BUILD)/dos/exfatsys.obj: drivers/exfat/exfatsys.c $(EXFATHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

$(BUILD)/dos/exfat.obj: common/exfat/exfat.c $(EXFATHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

$(BUILD)/dos/codepage.obj: common/exfat/codepage.c $(EXFATHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

# raw binary: the device header of exfatsys.asm at offset 0
$(DOSEXFAT): $(EXFATOBJ) drivers/exfat/exfat.mk
	$(WLINK) format raw bin option offset=0,quiet,nodefaultlibs,map=$(BUILD)/dos/EXFAT.map disable 1014,1023 \
		order clname CODE segment _HDR segment _TEXT clname DATA clname BSS clname STK clname INIT \
		$(foreach o,$(EXFATOBJ),file $(o)) library $(WATCOM)/lib286/dos/clibs.lib name $@
