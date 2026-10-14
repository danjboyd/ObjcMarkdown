include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = GPUpdaterUI

GPUpdaterUI_OBJC_FILES = Source/GPStandardUpdaterController.m
# Opening URLs goes through ShellExecuteW on Windows (Source/GPUpdaterUIShell.c).
GPUpdaterUI_C_FILES = Source/GPUpdaterUIShell.c
GPUpdaterUI_HEADER_FILES = Headers/GPStandardUpdaterController.h
GPUpdaterUI_HEADER_FILES_DIR = Headers
GPUpdaterUI_CPPFLAGS += -IHeaders -I../GPUpdaterCore/Headers
GPUpdaterUI_LIBRARIES_DEPEND_UPON += -lgnustep-gui -lgnustep-base
GPUpdaterUI_LIBRARIES_DEPEND_UPON += -L../GPUpdaterCore/$(GNUSTEP_OBJ_DIR) -lGPUpdaterCore
ifeq ($(GNUSTEP_TARGET_OS),mingw32)
GPUpdaterUI_LIBRARIES_DEPEND_UPON += -lshell32
endif

include $(GNUSTEP_MAKEFILES)/library.make
