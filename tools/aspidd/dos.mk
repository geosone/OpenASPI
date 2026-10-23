ROOT := $(abspath $(OPEN386MAX))
PROJ := ASPIDDGUI
SRCDIRS := tools/aspidd common/dos
ASMINC := include tools/aspidd $(ROOT)/INCLUDE $(ROOT)/INC $(ROOT)/QUILIB $(ROOT)/386MAX
CASEMAP := mx
CMODEL := l
CDEFS := DOS_VERSION OA_GUI
PROGS := ASPIDDG.EXE
ASPIDDG.EXE_OBJS := MAIN.OBJ RAW.OBJ RESCUE.OBJ COPYUI.OBJ
MAIN.OBJ_SRC := aspidd.c
RAW.OBJ_SRC := raw_client.c
RESCUE.OBJ_SRC := rescue_read.c
COPYUI.OBJ_SRC := copy_ui.c
ASPIDDG.EXE_LIBS := $(QUILIB)
ASPIDDG.EXE_STACK := 8192
include $(ROOT)/linux/mk/dos.mk
unexport JWASM JWLINK
$(addprefix $(OUT)/,$(COBJS)): include/openaspi/raw_media.h include/openaspi/rescue.h tools/aspidd/copy_ui.h
