# EXFAT.SYS and the exFAT host test; included by the Makefile.

DOSEXFAT := $(BUILD)/dos/EXFAT.SYS
EXFATTESTBIN := $(BUILD)/host/test_exfat
EXCHKTESTBIN := $(BUILD)/host/test_exchk
EXFMTTESTBIN := $(BUILD)/host/test_exfmt
EXFATCORE := common/exfat/exfat.c common/exfat/codepage.c
EXFATHDR := include/openaspi/exfat.h include/openaspi/exfatsys.h include/openaspi/exfat_check.h include/openaspi/exfat_format.h include/openaspi/types.h
EXFATOBJ := $(BUILD)/dos/exfatsys_a.obj $(BUILD)/dos/exfatsys.obj $(BUILD)/dos/exfat.obj $(BUILD)/dos/cpinit.obj
# small model, no stack checks, no C runtime start-up: CS = DS = SS
EXFATWCC := $(WCC) -q -ms -0 -os -s -zl -zdp -wx -we -Iinclude -I$(WATCOM)/h

$(EXFATTESTBIN): tests/exfat_test.c $(EXFATCORE) $(EXFATHDR)
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/exfat_test.c $(EXFATCORE)

$(EXCHKTESTBIN): tests/exchk_test.c common/exfat/exfat_check.c $(EXFATCORE) $(EXFATHDR)
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/exchk_test.c common/exfat/exfat_check.c $(EXFATCORE)

$(EXFMTTESTBIN): tests/exfmt_test.c common/exfat/exfat_format.c common/exfat/upcase.c $(EXFATHDR)
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/exfmt_test.c common/exfat/exfat_format.c common/exfat/upcase.c

$(BUILD)/dos/exfatsys_a.obj: drivers/exfat/exfatsys.asm | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -omf -0 -W4 -WX -Fo=$@ $<

$(BUILD)/dos/exfatsys.obj: drivers/exfat/exfatsys.c $(EXFATHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

$(BUILD)/dos/exfat.obj: common/exfat/exfat.c $(EXFATHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

$(BUILD)/dos/cpinit.obj: drivers/exfat/cpinit.c common/exfat/codepage.c $(EXFATHDR)
	mkdir -p $(@D)
	$(EXFATWCC) -fo=$@ $<

# raw binary: the device header of exfatsys.asm at offset 0
$(DOSEXFAT): $(EXFATOBJ) drivers/exfat/exfat.mk
	$(WLINK) format raw bin option offset=0,quiet,nodefaultlibs,map=$(BUILD)/dos/EXFAT.map disable 1014,1023 \
		order clname CODE segment _HDR segment _TEXT clname DATA clname BSS clname STK clname INIT \
		$(foreach o,$(EXFATOBJ),file $(o)) library $(WATCOM)/lib286/dos/clibs.lib name $@
