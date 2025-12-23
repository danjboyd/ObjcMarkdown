include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = ObjcMarkdown

CMARK_CFLAGS := $(shell pkg-config --cflags cmark 2>/dev/null)
CMARK_LIBS := $(shell pkg-config --libs cmark 2>/dev/null)

ObjcMarkdown_OBJC_FILES = OMMarkdownRenderer.m OMTheme.m
ObjcMarkdown_C_FILES = ../third_party/tomlc99/toml.c
ObjcMarkdown_HEADER_FILES = OMMarkdownRenderer.h OMTheme.h
ObjcMarkdown_CPPFLAGS += $(CMARK_CFLAGS) -I../third_party/tomlc99
ObjcMarkdown_LDFLAGS += $(CMARK_LIBS)
ObjcMarkdown_LIBRARIES += -lcmark

include $(GNUSTEP_MAKEFILES)/library.make
