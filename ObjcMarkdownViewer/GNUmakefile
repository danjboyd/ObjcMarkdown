include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = MarkdownViewer

CMARK_PKG := $(shell pkg-config --exists cmark 2>/dev/null && echo cmark || echo libcmark)
CMARK_LIBS := $(shell pkg-config --libs $(CMARK_PKG) 2>/dev/null)

MarkdownViewer_OBJC_FILES = main.m OMDAppDelegate.m OMDTextView.m OMDSourceTextView.m OMDSourceHighlighter.m OMDLineNumberRulerView.m OMDDocumentConverter.m OMDPandocConverter.m OMDPreviewSync.m OMDViewerModeState.m OMDCodeCopyButton.m OMDCopyFeedbackBadgeView.m OMDFormattingBarView.m OMDGitHubClient.m OMDInlineToggle.m OMDPanelSelection.m
MarkdownViewer_CPPFLAGS += -I../ObjcMarkdown
MarkdownViewer_CPPFLAGS += -I../third_party/libs-OpenSave/Headers
MarkdownViewer_CPPFLAGS += -I../third_party/TextViewVimKit/src
MarkdownViewer_CPPFLAGS += -I../third_party/GPUpdaterCore/Headers
MarkdownViewer_CPPFLAGS += -I../third_party/GPUpdaterUI/Headers
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
MarkdownViewer_OBJCFLAGS += -include sys/types.h "-Dmode_t=unsigned short"
MarkdownViewer_WINDRES_FILES = MarkdownViewer.rc
MarkdownViewer_LDFLAGS += -lgdi32
endif
MarkdownViewer_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR) -lObjcMarkdown -lcmark
MarkdownViewer_LDFLAGS += $(CMARK_LIBS)
MarkdownViewer_LDFLAGS += -L../third_party/libs-OpenSave/Source/$(GNUSTEP_OBJ_DIR) -lOpenSave
MarkdownViewer_LDFLAGS += -L../third_party/TextViewVimKitBuild/$(GNUSTEP_OBJ_DIR) -lTextViewVimKit
MarkdownViewer_LDFLAGS += -L../third_party/GPUpdaterCore/$(GNUSTEP_OBJ_DIR) -lGPUpdaterCore
MarkdownViewer_LDFLAGS += -L../third_party/GPUpdaterUI/$(GNUSTEP_OBJ_DIR) -lGPUpdaterUI
MarkdownViewer_LDFLAGS += -Wl,-rpath,'$$ORIGIN/../../ObjcMarkdownRuntime'
MarkdownViewer_LDFLAGS += -Wl,-rpath,'$$ORIGIN/../../../GNUstep/System/Library/Libraries'
MarkdownViewer_LDFLAGS += -ldispatch
MarkdownViewer_RESOURCE_FILES = ../Resources/theme-github.toml ../Resources/markdown_icon.png ../Resources/open-icon.png ../Resources/toolbar-open.png ../Resources/toolbar-import.png ../Resources/toolbar-saveas.png ../Resources/toolbar-export.png ../Resources/toolbar-print.png ../Resources/toolbar-explorer-toggle.png ../Resources/toolbar-preferences.png ../Resources/code-copy-icon.png
MarkdownViewer_APPLICATION_ICON = markdown_icon.png
MarkdownViewer_GSWAPP_INFO_PLIST = MarkdownViewerInfo.plist

include $(GNUSTEP_MAKEFILES)/application.make

after-all:: MarkdownViewerInfo.plist
	@if [ -d MarkdownViewer.app/Resources ]; then \
		cp MarkdownViewerInfo.plist MarkdownViewer.app/Resources/Info-gnustep.plist; \
	elif [ -d MarkdownViewer.app/Contents/Resources ]; then \
		cp MarkdownViewerInfo.plist MarkdownViewer.app/Contents/Resources/Info-gnustep.plist; \
	else \
		echo "Warning: could not locate bundle Resources directory to copy MarkdownViewerInfo.plist"; \
	fi
	@helper_path="../third_party/gp-update-helper/$(GNUSTEP_OBJ_DIR)/gp-update-helper$(EXEEXT)"; \
	if [ -f "$$helper_path" ]; then \
		if [ -f MarkdownViewer.app/MarkdownViewer$(EXEEXT) ]; then \
			cp "$$helper_path" MarkdownViewer.app/gp-update-helper$(EXEEXT); \
			chmod +x MarkdownViewer.app/gp-update-helper$(EXEEXT); \
		elif [ -f MarkdownViewer.app/Contents/MacOS/MarkdownViewer$(EXEEXT) ]; then \
			cp "$$helper_path" MarkdownViewer.app/Contents/MacOS/gp-update-helper$(EXEEXT); \
			chmod +x MarkdownViewer.app/Contents/MacOS/gp-update-helper$(EXEEXT); \
		else \
			echo "Warning: could not locate app executable directory to copy gp-update-helper"; \
		fi; \
	else \
		echo "Warning: gp-update-helper was not built at $$helper_path"; \
	fi
