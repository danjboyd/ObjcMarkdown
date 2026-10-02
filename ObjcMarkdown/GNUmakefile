include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = ObjcMarkdown

CMARK_PKG := $(shell pkg-config --exists cmark 2>/dev/null && echo cmark || echo libcmark)
CMARK_CFLAGS := $(shell pkg-config --cflags $(CMARK_PKG) 2>/dev/null)
CMARK_LIBS := $(shell pkg-config --libs $(CMARK_PKG) 2>/dev/null)
OBJCMARKDOWN_ENABLE_TOML_THEME ?= 1

ObjcMarkdown_OBJC_FILES = OMMarkdownRenderer.m OMRenderedObject.m OMTheme.m OMMarkdownParsingOptions.m OMAppKitSerialization.m OMMermaidERDiagram.m OMMermaidERLayout.m OMMermaidERDrawing.m
ObjcMarkdown_HEADER_FILES = OMMarkdownRenderer.h OMRenderedObject.h OMTheme.h OMMarkdownParsingOptions.h OMAppKitSerialization.h OMMermaidERDiagram.h OMMermaidERLayout.h OMMermaidERDrawing.h
ObjcMarkdown_CPPFLAGS += $(CMARK_CFLAGS) -DOBJCMARKDOWN_ENABLE_TOML_THEME=$(OBJCMARKDOWN_ENABLE_TOML_THEME)
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
ObjcMarkdown_OBJCFLAGS += -include sys/types.h "-Dmode_t=unsigned short"
ObjcMarkdown_LIBRARIES_DEPEND_UPON += -lgdiplus
endif
ifeq ($(OBJCMARKDOWN_ENABLE_TOML_THEME),1)
ObjcMarkdown_C_FILES = ../third_party/tomlc99/toml.c
ObjcMarkdown_CPPFLAGS += -I../third_party/tomlc99
endif
ObjcMarkdown_LIBRARIES_DEPEND_UPON += $(CMARK_LIBS) -lcmark -ldispatch

include $(GNUSTEP_MAKEFILES)/library.make
