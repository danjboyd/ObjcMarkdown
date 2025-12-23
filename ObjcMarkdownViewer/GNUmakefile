include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ObjcMarkdownViewer

ObjcMarkdownViewer_OBJC_FILES = main.m OMDAppDelegate.m OMDTextView.m
ObjcMarkdownViewer_CPPFLAGS += -I../ObjcMarkdown
ObjcMarkdownViewer_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR) -lObjcMarkdown -lcmark
ObjcMarkdownViewer_LDFLAGS += $(shell pkg-config --libs cmark 2>/dev/null)
ObjcMarkdownViewer_RESOURCE_FILES = ../Resources/theme-github.toml

include $(GNUSTEP_MAKEFILES)/application.make
