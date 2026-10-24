JWASM_DIR  ?= deps/JWasm
JWLINK_DIR ?= deps/jwlink
GDI        ?= deps/gdi
GDIINSTALL = $(GDI_OUT)/INSTALL.EXE
CC      ?= cc
WATCOM  ?= /opt/watcom
WCC     ?= $(WATCOM)/binl64/wcc
WLINK   ?= $(WATCOM)/binl64/wlink
OPEN386MAX ?= deps/Open386MAX
MAXLANG ?= US
ifeq ($(filter $(MAXLANG),US GR),)
$(error Unsupported MAXLANG '$(MAXLANG)'; use US or GR)
endif

BUILD   := build
GDI_OUT ?= $(abspath $(BUILD)/gdi)
TOOLSDIR := $(BUILD)/tools
JWASM   ?= $(TOOLSDIR)/jwasm/jwasm
JWLINK  ?= $(TOOLSDIR)/jwlink/jwlink
HOSTOBJ := $(BUILD)/host/tape_cdb.o $(BUILD)/host/tape_sense.o
TESTBIN := $(BUILD)/host/test_tape
ASPITESTBIN := $(BUILD)/host/test_aspi
FATTESTBIN := $(BUILD)/host/test_fat_format
RESCUETESTBIN := $(BUILD)/host/test_rescue
NATIVEAPITESTBIN := $(BUILD)/host/test_native_tape_api
DOSDRV  := $(BUILD)/dos/ASPITAP.SYS
DOSCDA  := $(BUILD)/dos/ASPICDA.SYS
DOSDSK  := $(BUILD)/dos/ASPIDSK.SYS
DOSFDD  := $(BUILD)/dos/ASPIFDD.SYS
SHSUCD  ?= deps/shsucd
NASM    ?= nasm
DOSSHSUCDX := $(BUILD)/dos/SHSUCDX.COM
DOSCDAUDIO := $(BUILD)/dos/CDAUDIO.COM
DOSSCAN := $(BUILD)/dos/ASPISCAN.COM
DOSCTL := $(BUILD)/dos/ASPICTL.EXE
DOSFMT := $(BUILD)/dos/ASPIFMT.EXE
DOSDD := $(BUILD)/dos/ASPIDD.EXE
DOSDDGUI := $(BUILD)/$(MAXLANG)/dos/ASPIDDG.EXE
CTL_COMMANDS := $(shell sed -n 's/^OA_COMMAND(\([A-Z0-9]*\)).*/\1/p' tools/aspictl/commands.def)
DOSCTLALIASES := $(addprefix $(BUILD)/dos/,$(addsuffix .EXE,$(CTL_COMMANDS)))
DOSMGR := $(BUILD)/$(MAXLANG)/dos/ASPIMGR.EXE
QUILIB := $(abspath $(BUILD)/tools/quilib-$(MAXLANG)/LQUILIBR.LIB)
QUIJWASM := $(abspath $(BUILD)/tools/qui-jwasm/jwasm)
DOSTAPECTL := $(BUILD)/dos/TAPECTL.COM
DOSAPIINFO := $(BUILD)/dos/OTAPINFO.EXE
DOSWINCHECK := $(BUILD)/dos/WINCHECK.COM
WIN16CHECK := $(BUILD)/win16/WINCHECK.EXE
WIN16CHECKOBJ := $(BUILD)/win16/wincheck.obj
DOSCOBJ := $(BUILD)/dos/tape_cdb.obj $(BUILD)/dos/tape_sense.obj $(BUILD)/dos/tape_abi.obj
DISTDIR := $(BUILD)/dist
RELEASEDIR ?= release

CFLAGS  ?= -std=c90 -Wall -Wextra -Werror -pedantic -O2
CPPFLAGS += -Iinclude

include drivers/exfat/exfat.mk
include tools/exchk/exchk.mk
include tools/aspichk/aspichk.mk
include tools/exfmt/exfmt.mk

.PHONY: exfat-dist all tools test check dos-c-check dos-smoke dos-cda-smoke dos-media-smoke dos-disk-smoke dos-tape-smoke dos-mhvtl-smoke dos-mhvtl-roundtrip dos-mhvtl-write-protect gdi-install dist disksets clean

all: $(DOSDRV) $(DOSCDA) $(DOSDSK) $(DOSFDD) $(DOSEXFAT) $(EXFATTESTBIN) $(DOSEXCHK) $(EXCHKTESTBIN) $(DOSASPICHK) $(FATCHKTESTBIN) $(DOSEXFMT) $(EXFMTTESTBIN) $(DOSSHSUCDX) $(DOSCDAUDIO) $(DOSSCAN) $(DOSMGR) $(DOSCTL) $(DOSCTLALIASES) $(DOSFMT) $(DOSDD) $(DOSDDGUI) $(DOSTAPECTL) $(DOSAPIINFO) $(DOSWINCHECK) $(WIN16CHECK) $(TESTBIN) $(ASPITESTBIN)

test: $(DOSDRV) $(DOSCDA) $(DOSDSK) $(DOSFDD) $(EXFATTESTBIN) $(TESTBIN) $(ASPITESTBIN) $(FATTESTBIN) $(RESCUETESTBIN) $(NATIVEAPITESTBIN)
	$(TESTBIN)
	$(ASPITESTBIN)
	$(FATTESTBIN)
	$(RESCUETESTBIN)
	$(NATIVEAPITESTBIN)
	$(EXFATTESTBIN)
	sh tests/dos_driver_layout.sh $(DOSDRV)
	sh tests/dos_cda_layout.sh $(DOSCDA)
	sh tests/dos_block_layout.sh $(DOSDSK)
	sh tests/dos_block_layout.sh $(DOSFDD)

check: tools all test dos-c-check

$(FATTESTBIN): tests/fat_format_test.c common/dos/fat_format.c include/openaspi/fat_format.h include/openaspi/types.h
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/fat_format_test.c common/dos/fat_format.c

$(NATIVEAPITESTBIN): tests/native_tape_api_test.c common/tape/tape_api.c include/openaspi/tape_api.h include/openaspi/types.h
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/native_tape_api_test.c common/tape/tape_api.c

$(RESCUETESTBIN): tests/rescue_test.c common/dos/rescue_read.c include/openaspi/rescue.h include/openaspi/types.h
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ tests/rescue_test.c common/dos/rescue_read.c

tools: $(JWASM) $(JWLINK)

$(JWASM):
	$(MAKE) -C $(JWASM_DIR) -f GccUnix.mak OUTD=$(abspath $(@D))

$(JWLINK):
	$(MAKE) -C $(JWLINK_DIR) -f GccUnix.mak OUTD=$(abspath $(@D)) \
		outd_wres=$(abspath $(TOOLSDIR)/jwlink-wres)

dos-c-check: $(DOSCOBJ)

dos-smoke: all
	bash tests/dos_scan.sh

dos-cda-smoke: all
	bash tests/dos_cda.sh
	BUS=ide bash tests/dos_cda.sh

dos-disk-smoke: all
	bash tests/dos_block_ownership.sh
	bash tests/dos_disk.sh
	DETECT_ONLY=1 bash tests/dos_disk.sh

dos-media-smoke: all
	bash tests/dos_media_control.sh

dos-tape-smoke: all
	bash tests/dos_tape_ioctl.sh

dos-mhvtl-smoke: all
	bash tests/dos_mhvtl.sh

dos-mhvtl-roundtrip: all
	MHVTL_WRITE_TEST=1 bash tests/dos_mhvtl.sh

dos-mhvtl-write-protect: all
	MHVTL_WRITE_TEST=1 MHVTL_WRITE_PROTECT_TEST=1 bash tests/dos_mhvtl.sh

dist: all gdi-install LICENSE tests/dist_layout.sh tools/package/localize.py installer/lang/GR.json installer/README.GR.TXT
	rm -rf $(DISTDIR)
	mkdir -p $(DISTDIR)
	cp $(DOSDRV) $(DOSCDA) $(DOSDSK) $(DOSFDD) $(DOSSHSUCDX) $(DOSCDAUDIO) $(DOSSCAN) $(DOSTAPECTL) $(DOSAPIINFO) $(DOSWINCHECK) $(WIN16CHECK) $(GDIINSTALL) installer/INSTALL.INI \
		installer/README.TXT LICENSE $(DISTDIR)/
	cp $(DOSMGR) $(DISTDIR)/
	cp $(DOSCTL) $(DOSCTLALIASES) $(DISTDIR)/
	cp $(DOSFMT) $(DOSDD) $(DISTDIR)/
	cp $(DOSDDGUI) $(DISTDIR)/
	cp $(DOSEXFAT) $(DOSEXFMT) $(DOSEXCHK) $(DISTDIR)/
	mv $(DISTDIR)/LICENSE $(DISTDIR)/LICENSE.TXT
	cp $(SHSUCD)/LICENSE.txt $(DISTDIR)/SHSUCD.LIC
	cp $(SHSUCD)/readme.txt $(DISTDIR)/SHSUCD.TXT
	python3 tools/package/localize.py $(MAXLANG) $(DISTDIR)
	sh tests/dist_layout.sh $(DISTDIR) $(SHSUCD)

# the exFAT package: the same files as the exFAT option of OpenASPI
EXFATVERSION := $(shell sed -n 's/^\#define VERSION "\(.*\)"/\1/p' drivers/exfat/exfatsys.c)
exfat-dist: $(DOSEXFAT) $(DOSEXFMT) $(DOSEXCHK) gdi-install LICENSE tools/package/localize.py installer/exfat/INSTALL.INI
	rm -rf $(DISTDIR)
	mkdir -p $(DISTDIR)
	cp $(DOSEXFAT) $(DOSEXFMT) $(DOSEXCHK) $(GDIINSTALL) $(DISTDIR)/
	cp LICENSE $(DISTDIR)/LICENSE.TXT
	python3 tools/package/localize.py $(MAXLANG) $(DISTDIR) exfat

gdi-install:
	$(MAKE) -C $(GDI) OUT=$(GDI_OUT)

# Build languages sequentially; shared drivers/CLI and GDI are reused.
disksets: gdi-install
	$(MAKE) -o gdi-install MAXLANG=US DISTDIR=$(BUILD)/packages/US dist
	bash tools/package/mkdisks.sh US $(BUILD)/packages/US $(RELEASEDIR)/US
	$(MAKE) -o gdi-install MAXLANG=GR DISTDIR=$(BUILD)/packages/GR dist
	bash tools/package/mkdisks.sh GR $(BUILD)/packages/GR $(RELEASEDIR)/GR
	$(MAKE) -o gdi-install MAXLANG=US DISTDIR=$(BUILD)/packages/exfat-US exfat-dist
	bash tools/package/mkexfat.sh US $(BUILD)/packages/exfat-US $(RELEASEDIR)/US $(EXFATVERSION)
	$(MAKE) -o gdi-install MAXLANG=GR DISTDIR=$(BUILD)/packages/exfat-GR exfat-dist
	bash tools/package/mkexfat.sh GR $(BUILD)/packages/exfat-GR $(RELEASEDIR)/GR $(EXFATVERSION)

$(DOSDRV): drivers/aspitap/aspitap.asm common/aspi/dos_aspi.inc common/aspi/tape_sense.inc \
		common/aspi/native_tape.inc common/aspi/native_tape_defs.inc common/aspi/native_tape_read.inc common/aspi/native_tape_write.inc | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPITAP.lst -Fw$(BUILD)/dos/ASPITAP.err -Fo=$@ $<

$(DOSCDA): drivers/aspicda/aspicda.asm common/aspi/dos_aspi.inc common/aspi/aspi_client.inc \
		common/aspi/aspi_init.inc common/aspi/media_control.inc common/dos/devreq.inc | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPICDA.lst -Fw$(BUILD)/dos/ASPICDA.err -Fo=$@ $<

BLKDEPS := common/dos/blkdrv.inc common/aspi/dos_aspi.inc common/aspi/aspi_client.inc \
		common/aspi/aspi_init.inc common/aspi/removable.inc common/aspi/media_control.inc common/dos/devreq.inc
BLKDEPS += common/dos/raw_media.inc common/dos/block_capacity.inc common/dos/block_params.inc common/dos/block_track.inc common/dos/exfat_svc.inc

$(DOSDSK): drivers/aspidsk/aspidsk.asm $(BLKDEPS) | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPIDSK.lst -Fw$(BUILD)/dos/ASPIDSK.err -Fo=$@ $<

$(DOSFDD): drivers/aspifdd/aspifdd.asm $(BLKDEPS) | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPIFDD.lst -Fw$(BUILD)/dos/ASPIFDD.err -Fo=$@ $<

# SHSUCDX 4.00 with digital CD audio (/A:ON|OFF|AUTO) for VSBHDA and
# CDAUDIO.COM to switch it at run time, from deps/shsucd
$(DOSSHSUCDX): $(SHSUCD)/shsucdx.nsm
	mkdir -p $(@D)
	cd $(SHSUCD) && $(NASM) -O9 -w-all -o $(abspath $@) shsucdx.nsm

$(DOSCDAUDIO): $(SHSUCD)/cdaudio.asm
	mkdir -p $(@D)
	$(NASM) -f bin -o $@ $<

$(DOSSCAN): tools/aspiscan/aspiscan.asm common/aspi/dos_aspi.inc common/aspi/removable.inc | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPISCAN.lst -Fw$(BUILD)/dos/ASPISCAN.err -Fo=$@ $<

$(BUILD)/dos/aspictl.obj: tools/aspictl/aspictl.c tools/aspictl/commands.def
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=$(WATCOM)/h -fo=$@ $<

$(DOSCTL): $(BUILD)/dos/aspictl.obj Makefile
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ file $< \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=4096

$(DOSCTLALIASES): $(DOSCTL)
	cp $< $@

$(BUILD)/dos/raw_client.obj: common/dos/raw_client.c include/openaspi/raw_media.h include/openaspi/rescue.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/dos/fat_format.obj: common/dos/fat_format.c include/openaspi/fat_format.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/dos/aspifmt.obj: tools/aspifmt/aspifmt.c include/openaspi/raw_media.h include/openaspi/fat_format.h include/openaspi/rescue.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/dos/aspidd.obj: tools/aspidd/aspidd.c include/openaspi/raw_media.h include/openaspi/rescue.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/dos/rescue_read.obj: common/dos/rescue_read.c include/openaspi/rescue.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(DOSFMT): $(BUILD)/dos/aspifmt.obj $(BUILD)/dos/raw_client.obj $(BUILD)/dos/fat_format.obj $(BUILD)/dos/rescue_read.obj Makefile
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ \
		file $(BUILD)/dos/aspifmt.obj,$(BUILD)/dos/raw_client.obj,$(BUILD)/dos/fat_format.obj,$(BUILD)/dos/rescue_read.obj \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=4096

$(DOSDD): $(BUILD)/dos/aspidd.obj $(BUILD)/dos/raw_client.obj $(BUILD)/dos/rescue_read.obj Makefile
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ \
		file $(BUILD)/dos/aspidd.obj,$(BUILD)/dos/raw_client.obj,$(BUILD)/dos/rescue_read.obj \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=4096

$(DOSDDGUI): tools/aspidd/aspidd.c tools/aspidd/copy_ui.c tools/aspidd/copy_ui.h \
		tools/aspidd/dos.mk common/dos/raw_client.c common/dos/rescue_read.c \
		include/openaspi/raw_media.h include/openaspi/rescue.h include/openaspi/types.h $(QUILIB) | $(JWASM) $(JWLINK)
	$(MAKE) -f tools/aspidd/dos.mk OPEN386MAX=$(abspath $(OPEN386MAX)) \
		OUT=$(abspath $(BUILD)/$(MAXLANG)/aspidd-obj) BINDIR=$(abspath $(@D)) \
		QUILIB=$(QUILIB) MAXLANG=$(MAXLANG) WATCOM=$(WATCOM) \
		JWASM=$(abspath $(JWASM)) JWLINK=$(abspath $(JWLINK)) $(abspath $@)

$(QUIJWASM): $(OPEN386MAX)/linux/jwasm/GccUnix.mak \
		$(wildcard $(OPEN386MAX)/linux/jwasm/src/*.c $(OPEN386MAX)/linux/jwasm/src/H/*.h)
	$(MAKE) -C $(OPEN386MAX)/linux/jwasm -f GccUnix.mak OUTD=$(abspath $(@D))

$(QUILIB): tools/aspimgr/quilib.mk \
		$(wildcard $(OPEN386MAX)/QUILIB/*.C $(OPEN386MAX)/QUILIB/*.ASM \
		$(OPEN386MAX)/INCLUDE/*.H $(OPEN386MAX)/INC/*.INC) | $(QUIJWASM) $(JWLINK)
	$(MAKE) -C $(OPEN386MAX)/QUILIB -f $(abspath tools/aspimgr/quilib.mk) \
		OUT=$(patsubst %/,%,$(dir $(QUILIB))) \
		BINDIR=$(dir $(QUILIB))bin \
		JWASM=$(QUIJWASM) JWLINK=$(abspath $(JWLINK)) WATCOM=$(WATCOM) \
		MAXLANG=$(MAXLANG) $@

$(DOSMGR): tools/aspimgr/main.c tools/aspimgr/aspiio.asm tools/aspimgr/dos.mk \
		include/openaspi/aspi.h include/openaspi/types.h $(QUILIB) | $(JWASM) $(JWLINK)
	$(MAKE) -f tools/aspimgr/dos.mk OPEN386MAX=$(abspath $(OPEN386MAX)) \
		OUT=$(abspath $(BUILD)/$(MAXLANG)/aspimgr-obj) BINDIR=$(abspath $(@D)) \
		QUILIB=$(QUILIB) MAXLANG=$(MAXLANG) WATCOM=$(WATCOM) \
		JWASM=$(abspath $(JWASM)) JWLINK=$(abspath $(JWLINK)) $(abspath $@)

$(DOSTAPECTL): tools/tapectl/tapectl.asm | $(JWASM)
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/TAPECTL.lst -Fw$(BUILD)/dos/TAPECTL.err -Fo=$@ $<

$(DOSAPIINFO): $(BUILD)/dos/otapinfo.obj $(BUILD)/dos/tape_api.obj
	WATCOM=$(WATCOM) $(WLINK) format dos name $@ file $(BUILD)/dos/otapinfo.obj,$(BUILD)/dos/tape_api.obj \
		libpath $(WATCOM)/lib286/dos libpath $(WATCOM)/lib286 option quiet,stack=4096

$(BUILD)/dos/otapinfo.obj: tools/otapinfo/otapinfo.c include/openaspi/tape_api.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

$(BUILD)/dos/tape_api.obj: common/tape/tape_api.c include/openaspi/tape_api.h include/openaspi/types.h
	mkdir -p $(@D)
	WATCOM=$(WATCOM) $(WCC) -q -bt=dos -ms -0 -w4 -we -zq -os -s -i=include -i=$(WATCOM)/h -fo=$@ $<

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

$(BUILD)/dos/tape_abi.obj: tests/tape_abi.c include/openaspi/aspitape.h include/openaspi/tape_api.h include/openaspi/types.h
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
