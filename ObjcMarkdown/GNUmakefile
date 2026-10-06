include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = ObjcMarkdown

# cmark-gfm is vendored (see third_party/cmark-gfm/README.md) and compiled in.
CMARK_GFM_DIR = ../third_party/cmark-gfm
CMARK_GFM_C_FILES = $(wildcard $(CMARK_GFM_DIR)/src/*.c) $(wildcard $(CMARK_GFM_DIR)/extensions/*.c)
CMARK_GFM_CPPFLAGS = -I$(CMARK_GFM_DIR)/compat -I$(CMARK_GFM_DIR)/src -I$(CMARK_GFM_DIR)/extensions -DCMARK_GFM_STATIC_DEFINE
OBJCMARKDOWN_ENABLE_TOML_THEME ?= 1

ObjcMarkdown_OBJC_FILES = OMMarkdownRenderer.m OMMarkdownRendererCode.m OMMarkdownRendererImages.m OMMarkdownRendererMath.m OMMarkdownRendererMermaid.m OMMarkdownRendererSource.m OMMarkdownRendererTables.m OMGFMParser.m OMBlockSignatureIndex.m OMRenderedObject.m OMTextTable.m OMStrikethroughLayoutManager.m OMTheme.m OMMarkdownParsingOptions.m OMAppKitSerialization.m OMMermaidERDiagram.m OMMermaidERLayout.m OMMermaidERDrawing.m OMMermaidFlowchart.m OMMermaidFlowchartLayout.m OMMermaidFlowchartDrawing.m
ObjcMarkdown_HEADER_FILES = OMExport.h OMMarkdownRenderer.h OMGFMParser.h OMBlockSignatureIndex.h OMRenderedObject.h OMTextTable.h OMStrikethroughLayoutManager.h OMTheme.h OMMarkdownParsingOptions.h OMAppKitSerialization.h OMMermaidERDiagram.h OMMermaidERLayout.h OMMermaidERDrawing.h OMMermaidFlowchart.h OMMermaidFlowchartLayout.h OMMermaidFlowchartDrawing.h
ObjcMarkdown_C_FILES = $(CMARK_GFM_C_FILES)
ObjcMarkdown_CPPFLAGS += $(CMARK_GFM_CPPFLAGS) -DOBJCMARKDOWN_ENABLE_TOML_THEME=$(OBJCMARKDOWN_ENABLE_TOML_THEME)
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
ObjcMarkdown_LIBRARIES_DEPEND_UPON += -lgdiplus
endif
ifeq ($(OBJCMARKDOWN_ENABLE_TOML_THEME),1)
ObjcMarkdown_C_FILES += ../third_party/tomlc99/toml.c
ObjcMarkdown_CPPFLAGS += -I../third_party/tomlc99
endif
ObjcMarkdown_LIBRARIES_DEPEND_UPON += -ldispatch

# make OMD_WERROR=1 (Linux CI): warnings in this code are errors.
ifneq ($(OMD_WERROR),)
ObjcMarkdown_OBJCFLAGS += -Werror
endif
include $(GNUSTEP_MAKEFILES)/library.make
