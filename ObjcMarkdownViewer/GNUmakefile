include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ObjcMarkdownViewer

CMARK_PKG := $(shell pkg-config --exists cmark 2>/dev/null && echo cmark || echo libcmark)
CMARK_LIBS := $(shell pkg-config --libs $(CMARK_PKG) 2>/dev/null)

ObjcMarkdownViewer_OBJC_FILES = main.m OMDAppDelegate.m OMDTextView.m OMDSourceTextView.m OMDSourceHighlighter.m OMDLineNumberRulerView.m OMDDocumentConverter.m OMDPandocConverter.m OMDPreviewSync.m OMDViewerModeState.m OMDCodeCopyButton.m OMDCopyFeedbackBadgeView.m OMDFormattingBarView.m OMDGitHubClient.m
ObjcMarkdownViewer_CPPFLAGS += -I../ObjcMarkdown
ObjcMarkdownViewer_CPPFLAGS += -I../third_party/libs-OpenSave/Headers
ObjcMarkdownViewer_CPPFLAGS += -I../third_party/TextViewVimKit/src
ObjcMarkdownViewer_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR) -lObjcMarkdown -lcmark
ObjcMarkdownViewer_LDFLAGS += $(CMARK_LIBS)
ObjcMarkdownViewer_LDFLAGS += -L../third_party/libs-OpenSave/Source/$(GNUSTEP_OBJ_DIR) -lOpenSave
ObjcMarkdownViewer_LDFLAGS += -L../third_party/TextViewVimKitBuild/$(GNUSTEP_OBJ_DIR) -lTextViewVimKit
ObjcMarkdownViewer_LDFLAGS += -Wl,-rpath,$(CURDIR)/../ObjcMarkdown/$(GNUSTEP_OBJ_DIR)
ObjcMarkdownViewer_LDFLAGS += -Wl,-rpath,$(CURDIR)/../third_party/libs-OpenSave/Source/$(GNUSTEP_OBJ_DIR)
ObjcMarkdownViewer_LDFLAGS += -Wl,-rpath,$(CURDIR)/../third_party/TextViewVimKitBuild/$(GNUSTEP_OBJ_DIR)
ObjcMarkdownViewer_LDFLAGS += -ldispatch
ObjcMarkdownViewer_RESOURCE_FILES = ../Resources/theme-github.toml ../Resources/markdown_icon.png ../Resources/open-icon.png ../Resources/toolbar-open.png ../Resources/toolbar-import.png ../Resources/toolbar-saveas.png ../Resources/toolbar-export.png ../Resources/toolbar-print.png ../Resources/toolbar-explorer-toggle.png ../Resources/code-copy-icon.png
ObjcMarkdownViewer_APPLICATION_ICON = markdown_icon.png

include $(GNUSTEP_MAKEFILES)/application.make
