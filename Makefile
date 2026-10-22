JWASM_DIR  ?= deps/JWasm
JWLINK_DIR ?= deps/jwlink
GDI        ?= deps/gdi
GDIINSTALL := $(GDI)/build/INSTALL.EXE
CC      ?= cc
WATCOM  ?= /opt/watcom
WCC     ?= $(WATCOM)/binl64/wcc
WLINK   ?= $(WATCOM)/binl64/wlink

BUILD   := build
TOOLSDIR := $(BUILD)/tools
JWASM   ?= $(TOOLSDIR)/jwasm/jwasm
JWLINK  ?= $(TOOLSDIR)/jwlink/jwlink
HOSTOBJ := $(BUILD)/host/tape_cdb.o $(BUILD)/host/tape_sense.o
TESTBIN := $(BUILD)/host/test_tape
ASPITESTBIN := $(BUILD)/host/test_aspi
DOSDRV  := $(BUILD)/dos/ASPITAP.SYS
DOSSCAN := $(BUILD)/dos/ASPISCAN.COM
DOSTAPECTL := $(BUILD)/dos/TAPECTL.COM
DOSWINCHECK := $(BUILD)/dos/WINCHECK.COM
WIN16CHECK := $(BUILD)/win16/WINCHECK.EXE
WIN16CHECKOBJ := $(BUILD)/win16/wincheck.obj
DOSCOBJ := $(BUILD)/dos/tape_cdb.obj $(BUILD)/dos/tape_sense.obj $(BUILD)/dos/tape_abi.obj
DISTDIR := $(BUILD)/dist

CFLAGS  ?= -std=c90 -Wall -Wextra -Werror -pedantic -O2
CPPFLAGS += -Iinclude

.PHONY: all tools test check dos-c-check dos-smoke dos-tape-smoke dos-mhvtl-smoke dos-mhvtl-roundtrip dos-mhvtl-write-protect gdi-install dist clean

all: $(DOSDRV) $(DOSSCAN) $(DOSTAPECTL) $(DOSWINCHECK) $(WIN16CHECK) $(TESTBIN) $(ASPITESTBIN)

test: $(DOSDRV) $(TESTBIN) $(ASPITESTBIN)
	$(TESTBIN)
	$(ASPITESTBIN)
	sh tests/dos_driver_layout.sh $(DOSDRV)

check: tools all test dos-c-check

tools: $(JWASM) $(JWLINK)

$(JWASM):
	$(MAKE) -C $(JWASM_DIR) -f GccUnix.mak OUTD=$(abspath $(@D))

$(JWLINK):
	$(MAKE) -C $(JWLINK_DIR) -f GccUnix.mak OUTD=$(abspath $(@D)) \
		outd_wres=$(abspath $(TOOLSDIR)/jwlink-wres)

dos-c-check: $(DOSCOBJ)

dos-smoke: all
	bash tests/dos_scan.sh

dos-tape-smoke: all
	bash tests/dos_tape_ioctl.sh

dos-mhvtl-smoke: all
	bash tests/dos_mhvtl.sh

dos-mhvtl-roundtrip: all
	MHVTL_WRITE_TEST=1 bash tests/dos_mhvtl.sh

dos-mhvtl-write-protect: all
	MHVTL_WRITE_TEST=1 MHVTL_WRITE_PROTECT_TEST=1 bash tests/dos_mhvtl.sh

dist: all gdi-install LICENSE
	rm -rf $(DISTDIR)
	mkdir -p $(DISTDIR)
	cp $(DOSDRV) $(DOSSCAN) $(DOSTAPECTL) $(DOSWINCHECK) $(WIN16CHECK) $(GDIINSTALL) installer/INSTALL.INI \
		installer/README.TXT LICENSE $(DISTDIR)/
	mv $(DISTDIR)/LICENSE $(DISTDIR)/LICENSE.TXT
	for f in ASPIDSK.SYS ASPIFDD.SYS ASPICDA.SYS; do \
		test ! -f $(BUILD)/dos/$$f || cp $(BUILD)/dos/$$f $(DISTDIR)/; \
	done

gdi-install:
	$(MAKE) -C $(GDI)

$(DOSDRV): drivers/aspitap/aspitap.asm common/aspi/dos_aspi.inc | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPITAP.lst -Fw$(BUILD)/dos/ASPITAP.err -Fo=$@ $<

$(DOSSCAN): tools/aspiscan/aspiscan.asm common/aspi/dos_aspi.inc | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPISCAN.lst -Fw$(BUILD)/dos/ASPISCAN.err -Fo=$@ $<

$(DOSTAPECTL): tools/tapectl/tapectl.asm | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/TAPECTL.lst -Fw$(BUILD)/dos/TAPECTL.err -Fo=$@ $<

$(DOSWINCHECK): tools/wincheck/wincheck.asm | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/WINCHECK.lst -Fw$(BUILD)/dos/WINCHECK.err -Fo=$@ $<

$(WIN16CHECKOBJ): tools/wincheck/wincheck.c
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=windows -ms -0 -zW -w4 -we -zq -os -s \
		-i=$(WATCOM)/h/win -fo=$@ $<

$(WIN16CHECK): $(WIN16CHECKOBJ)
	WATCOM=$(WATCOM) $(WLINK) format windows name $@ file $< \
		libpath $(WATCOM)/lib286/win libpath $(WATCOM)/lib286 \
		library windows,clibs option quiet,heapsize=1024,stack=4096,version=3.10

$(BUILD)/dos/tape_cdb.obj: common/scsi/tape_cdb.c include/openaspi/scsi_tape.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/dos/tape_abi.obj: tests/tape_abi.c include/openaspi/aspitape.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/dos/tape_sense.obj: common/scsi/tape_sense.c include/openaspi/scsi_tape.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/host/tape_cdb.o: common/scsi/tape_cdb.c include/openaspi/scsi_tape.h include/openaspi/types.h
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

$(BUILD)/host/tape_sense.o: common/scsi/tape_sense.c include/openaspi/scsi_tape.h include/openaspi/types.h
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

$(TESTBIN): tests/test_tape.c $(HOSTOBJ) include/openaspi/aspitape.h
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/test_tape.c $(HOSTOBJ)

$(ASPITESTBIN): tests/test_aspi.c include/openaspi/aspi.h include/openaspi/types.h
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/test_aspi.c

clean:
	rm -rf $(BUILD)
