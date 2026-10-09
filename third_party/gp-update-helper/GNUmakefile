include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = gp-update-helper

# The helper doesn't link GPUpdaterCore; it builds the download code itself.
gp-update-helper_OBJC_FILES = Source/main.m ../GPUpdaterCore/Source/GPUpdaterDownload.m
gp-update-helper_C_FILES = Source/monocypher/monocypher.c Source/monocypher/monocypher-ed25519.c ../GPUpdaterCore/Source/GPUpdaterWinHTTP.c
gp-update-helper_CPPFLAGS += -I../GPUpdaterCore/Headers
gp-update-helper_TOOL_LIBS += -lgnustep-base
ifeq ($(GNUSTEP_TARGET_OS),mingw32)
gp-update-helper_TOOL_LIBS += -lwinhttp
endif

include $(GNUSTEP_MAKEFILES)/tool.make
