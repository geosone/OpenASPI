TOOLROOT ?= ../386MAX/linux
GDI      ?= ../gdi
JWASM   ?= $(TOOLROOT)/bin/jwasm
JWLINK  ?= $(TOOLROOT)/bin/jwlink
CC      ?= cc
WATCOM  ?= /opt/watcom
WCC     ?= $(WATCOM)/binl64/wcc

BUILD   := build
HOSTOBJ := $(BUILD)/host/tape_cdb.o $(BUILD)/host/tape_sense.o
TESTBIN := $(BUILD)/host/test_tape
DOSDRV  := $(BUILD)/dos/ASPITAP.SYS
DOSCOBJ := $(BUILD)/dos/tape_cdb.obj $(BUILD)/dos/tape_sense.obj
DISTDIR := $(BUILD)/dist

CFLAGS  ?= -std=c90 -Wall -Wextra -Werror -pedantic -O2
CPPFLAGS += -Iinclude

.PHONY: all test check dos-c-check dist clean

all: $(DOSDRV) $(TESTBIN)

test: $(TESTBIN)
	$(TESTBIN)

check: all test dos-c-check

dos-c-check: $(DOSCOBJ)

dist: all $(GDI)/build/INSTALL.EXE LICENSE
	rm -rf $(DISTDIR)
	mkdir -p $(DISTDIR)
	cp $(DOSDRV) $(GDI)/build/INSTALL.EXE installer/INSTALL.INI \
		installer/README.TXT LICENSE $(DISTDIR)/
	mv $(DISTDIR)/LICENSE $(DISTDIR)/LICENSE.TXT
	for f in ASPIDSK.SYS ASPIFDD.SYS ASPICDA.SYS; do \
		test ! -f $(BUILD)/dos/$$f || cp $(BUILD)/dos/$$f $(DISTDIR)/; \
	done

$(GDI)/build/INSTALL.EXE:
	$(MAKE) -C $(GDI)

$(DOSDRV): drivers/aspitap/aspitap.asm
	mkdir -p $(@D)
	$(JWASM) -q -bin -0 -W4 -WX -Fl=$(BUILD)/dos/ASPITAP.lst -Fw$(BUILD)/dos/ASPITAP.err -Fo=$@ $<

$(BUILD)/dos/tape_cdb.obj: common/scsi/tape_cdb.c include/openaspi/scsi_tape.h include/openaspi/types.h
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

clean:
	rm -rf $(BUILD)
