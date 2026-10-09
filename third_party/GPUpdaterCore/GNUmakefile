include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = GPUpdaterCore

GPUpdaterCore_OBJC_FILES = Source/GPUpdater.m Source/GPUpdaterDownload.m
GPUpdaterCore_C_FILES = Source/GPUpdaterWinHTTP.c
GPUpdaterCore_HEADER_FILES = Headers/GPUpdater.h Headers/GPUpdaterDownload.h
GPUpdaterCore_HEADER_FILES_DIR = Headers
GPUpdaterCore_LIBRARIES_DEPEND_UPON += -lgnustep-base
GPUpdaterCore_CPPFLAGS += -IHeaders
# Downloads go through WinHTTP on Windows (Source/GPUpdaterWinHTTP.c).
ifeq ($(GNUSTEP_TARGET_OS),mingw32)
GPUpdaterCore_LIBRARIES_DEPEND_UPON += -lwinhttp
endif

include $(GNUSTEP_MAKEFILES)/library.make
