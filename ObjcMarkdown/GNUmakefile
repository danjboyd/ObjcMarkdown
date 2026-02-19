include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = ObjcMarkdown

CMARK_PKG := $(shell pkg-config --exists cmark 2>/dev/null && echo cmark || echo libcmark)
CMARK_CFLAGS := $(shell pkg-config --cflags $(CMARK_PKG) 2>/dev/null)
CMARK_LIBS := $(shell pkg-config --libs $(CMARK_PKG) 2>/dev/null)
OBJCMARKDOWN_ENABLE_TOML_THEME ?= 1

ObjcMarkdown_OBJC_FILES = OMMarkdownRenderer.m OMTheme.m OMMarkdownParsingOptions.m
ObjcMarkdown_HEADER_FILES = OMMarkdownRenderer.h OMTheme.h OMMarkdownParsingOptions.h
ObjcMarkdown_CPPFLAGS += $(CMARK_CFLAGS) -DOBJCMARKDOWN_ENABLE_TOML_THEME=$(OBJCMARKDOWN_ENABLE_TOML_THEME)
ifeq ($(OBJCMARKDOWN_ENABLE_TOML_THEME),1)
ObjcMarkdown_C_FILES = ../third_party/tomlc99/toml.c
ObjcMarkdown_CPPFLAGS += -I../third_party/tomlc99
endif
ObjcMarkdown_LIBRARIES_DEPEND_UPON += $(CMARK_LIBS) -lcmark -ldispatch

include $(GNUSTEP_MAKEFILES)/library.make
