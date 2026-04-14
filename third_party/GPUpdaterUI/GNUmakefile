include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = GPUpdaterUI

GPUpdaterUI_OBJC_FILES = Source/GPStandardUpdaterController.m
GPUpdaterUI_HEADER_FILES = Headers/GPStandardUpdaterController.h
GPUpdaterUI_HEADER_FILES_DIR = Headers
GPUpdaterUI_CPPFLAGS += -IHeaders -I../GPUpdaterCore/Headers
GPUpdaterUI_LIBRARIES_DEPEND_UPON += -lgnustep-gui -lgnustep-base
GPUpdaterUI_LIBRARIES_DEPEND_UPON += -L../GPUpdaterCore/$(GNUSTEP_OBJ_DIR) -lGPUpdaterCore

include $(GNUSTEP_MAKEFILES)/library.make
