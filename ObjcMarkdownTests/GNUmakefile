include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ObjcMarkdownTests

ObjcMarkdownTests_OBJC_FILES = OMMarkdownRendererTests.m
ObjcMarkdownTests_CPPFLAGS += -I../ObjcMarkdown
ObjcMarkdownTests_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR)
ObjcMarkdownTests_LDFLAGS += $(shell pkg-config --libs cmark 2>/dev/null)
ObjcMarkdownTests_BUNDLE_LIBS += -lObjcMarkdown -lXCTest -lcmark

include $(GNUSTEP_MAKEFILES)/bundle.make
