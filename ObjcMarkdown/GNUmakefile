include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = ObjcMarkdown

CMARK_PKG := $(shell pkg-config --exists cmark 2>/dev/null && echo cmark || echo libcmark)
CMARK_CFLAGS := $(shell pkg-config --cflags $(CMARK_PKG) 2>/dev/null)
CMARK_LIBS := $(shell pkg-config --libs $(CMARK_PKG) 2>/dev/null)
CMARK_MANAGED_INCLUDE_WIN := $(if $(GP_GNUSTEP_CLI_ROOT),$(subst \,/,$(GP_GNUSTEP_CLI_ROOT))/clang64/include)
CMARK_MANAGED_INCLUDE := $(shell if [ -n "$$GP_GNUSTEP_CLI_ROOT" ]; then root="$$(cygpath -u "$$GP_GNUSTEP_CLI_ROOT" 2>/dev/null)"; if [ -n "$$root" ]; then printf '%s/clang64/include' "$$root"; fi; fi)
OBJCMARKDOWN_ENABLE_TOML_THEME ?= 1
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
ObjcMarkdown_OBJCFLAGS += -include sys/types.h "-Dmode_t=unsigned short"
ObjcMarkdown_LIBRARIES_DEPEND_UPON += -lgdiplus
ifeq ($(strip $(CMARK_CFLAGS)),)
ifneq ($(strip $(CMARK_MANAGED_INCLUDE)),)
CMARK_CFLAGS := -I$(CMARK_MANAGED_INCLUDE_WIN) -I$(CMARK_MANAGED_INCLUDE)
else
CMARK_CFLAGS := -I/clang64/include
endif
endif
endif

ObjcMarkdown_OBJC_FILES = OMMarkdownRenderer.m OMTheme.m OMMarkdownParsingOptions.m
ObjcMarkdown_HEADER_FILES = OMMarkdownRenderer.h OMTheme.h OMMarkdownParsingOptions.h
ObjcMarkdown_CPPFLAGS += $(CMARK_CFLAGS) -DOBJCMARKDOWN_ENABLE_TOML_THEME=$(OBJCMARKDOWN_ENABLE_TOML_THEME)
ifeq ($(OBJCMARKDOWN_ENABLE_TOML_THEME),1)
ObjcMarkdown_C_FILES = ../third_party/tomlc99/toml.c
ObjcMarkdown_CPPFLAGS += -I../third_party/tomlc99
endif
ObjcMarkdown_LIBRARIES_DEPEND_UPON += $(CMARK_LIBS) -lcmark -ldispatch

include $(GNUSTEP_MAKEFILES)/library.make
