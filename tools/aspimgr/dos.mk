# Reuse Open386MAX's QUILIB and DOS compiler/linker conventions.
ROOT := $(abspath $(OPEN386MAX))
PROJ := ASPIMGR
SRCDIRS := tools/aspimgr
ASMINC := include $(ROOT)/INCLUDE $(ROOT)/INC $(ROOT)/QUILIB $(ROOT)/386MAX
CASEMAP := mx
CMODEL := l
CDEFS := DOS_VERSION
PROGS := ASPIMGR.EXE
ASPIMGR.EXE_OBJS := MAIN.OBJ ASPIIO.OBJ
MAIN.OBJ_SRC := main.c
ASPIIO.OBJ_SRC := aspiio.asm
ASPIMGR.EXE_LIBS := $(QUILIB)
ASPIMGR.EXE_STACK := 8192
include $(ROOT)/linux/mk/dos.mk
unexport JWASM JWLINK
$(OUT)/MAIN.OBJ: include/openaspi/aspi.h include/openaspi/types.h

