include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ObjcMarkdownViewer

ObjcMarkdownViewer_OBJC_FILES = main.m OMDAppDelegate.m OMDTextView.m OMDSourceTextView.m OMDLineNumberRulerView.m OMDDocumentConverter.m OMDPandocConverter.m
ObjcMarkdownViewer_CPPFLAGS += -I../ObjcMarkdown
ObjcMarkdownViewer_CPPFLAGS += -I../third_party/libs-OpenSave/Headers
ObjcMarkdownViewer_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR) -lObjcMarkdown -lcmark
ObjcMarkdownViewer_LDFLAGS += $(shell pkg-config --libs cmark 2>/dev/null)
ObjcMarkdownViewer_LDFLAGS += -L../third_party/libs-OpenSave/Source/$(GNUSTEP_OBJ_DIR) -lOpenSave
ObjcMarkdownViewer_RESOURCE_FILES = ../Resources/theme-github.toml ../Resources/markdown_icon.png ../Resources/open-icon.png ../Resources/toolbar-open.png ../Resources/toolbar-import.png ../Resources/toolbar-saveas.png ../Resources/toolbar-export.png ../Resources/toolbar-print.png
ObjcMarkdownViewer_APPLICATION_ICON = markdown_icon.png

include $(GNUSTEP_MAKEFILES)/application.make
