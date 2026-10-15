include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = MarkdownViewer

MarkdownViewer_OBJC_FILES = main.m OMDAppDelegate.m OMDWindowController.m OMDTextView.m OMDOutlineController.m OMDSourceTextView.m OMDSourceHighlighter.m OMDLineNumberRulerView.m OMDDocumentConverter.m OMDPandocConverter.m OMDPreviewSync.m OMDViewerModeState.m OMDCodeCopyButton.m OMDInlineToggle.m OMDPanelSelection.m OMDViewerDiagnostics.m OMDViewerColors.m OMDMainWindow.m OMDFillViews.m OMDToolbarViews.m OMDWin11SplitView.m OMDTextFileSupport.m OMDExternalTools.m OMDLayoutMetrics.m OMDViewerDefaults.m OMDViewerImages.m OMDExplorerController.m OMDExplorerRoot.m OMDExplorerTree.m OMDRemoteDocument.m OMDRemoteDocumentBar.m OMDOpenLocationController.m OMDPreferencesController.m OMDControlSupport.m OMDFormattingBarController.m OMDDocumentTabsController.m OMDMarkdownDocument.m OMDDocumentWindows.m OMDMainMenu.m OMDToolbarController.m OMDStatusBarController.m OMDMainThread.m OMDCopyButtonsController.m OMDRenderScheduler.m OMDPreviewTextUpdate.m
MarkdownViewer_CPPFLAGS += -I../ObjcMarkdown
# The version About shows: VERSION at the top, or OMD_VERSION=... for a build.
OMD_VERSION ?= $(strip $(shell cat ../VERSION 2>/dev/null))
MarkdownViewer_CPPFLAGS += -DOMD_APP_VERSION=\"$(OMD_VERSION)\"
# cmark-gfm is compiled into libObjcMarkdown; the source highlighter uses it too.
MarkdownViewer_CPPFLAGS += -I../third_party/cmark-gfm/compat -I../third_party/cmark-gfm/src -I../third_party/cmark-gfm/extensions -DCMARK_GFM_STATIC_DEFINE
MarkdownViewer_CPPFLAGS += -I../third_party/TextViewVimKit/src
MarkdownViewer_CPPFLAGS += -I../third_party/GPUpdaterCore/Headers
MarkdownViewer_CPPFLAGS += -I../third_party/GPUpdaterUI/Headers
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
MarkdownViewer_WINDRES_FILES = MarkdownViewer.rc
MarkdownViewer_LDFLAGS += -lgdi32
endif
MarkdownViewer_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR) -lObjcMarkdown
MarkdownViewer_LDFLAGS += -L../third_party/TextViewVimKitBuild/$(GNUSTEP_OBJ_DIR) -lTextViewVimKit
MarkdownViewer_LDFLAGS += -L../third_party/GPUpdaterCore/$(GNUSTEP_OBJ_DIR) -lGPUpdaterCore
MarkdownViewer_LDFLAGS += -L../third_party/GPUpdaterUI/$(GNUSTEP_OBJ_DIR) -lGPUpdaterUI
MarkdownViewer_LDFLAGS += -Wl,-rpath,'$$ORIGIN/../../ObjcMarkdownRuntime'
MarkdownViewer_LDFLAGS += -Wl,-rpath,'$$ORIGIN/../../../GNUstep/System/Library/Libraries'
MarkdownViewer_LDFLAGS += -ldispatch
MarkdownViewer_RESOURCE_FILES = ../Resources/theme-github.toml ../Resources/theme-github-dark.toml ../Resources/markdown_icon.png $(wildcard ../Resources/icons/*-symbolic.png)
MarkdownViewer_APPLICATION_ICON = markdown_icon.png
MarkdownViewer_GSWAPP_INFO_PLIST = MarkdownViewerInfo.plist

# make OMD_WERROR=1 (Linux CI): warnings in this code are errors.
ifneq ($(OMD_WERROR),)
MarkdownViewer_OBJCFLAGS += -Werror
endif
include $(GNUSTEP_MAKEFILES)/application.make

# The bundle's Info-gnustep.plist is MarkdownViewerInfo.plist plus the
# version keys, from OMD_VERSION, so the version is kept in one place (#119).
after-all:: MarkdownViewerInfo.plist
	@if [ -d MarkdownViewer.app/Resources ]; then \
		info=MarkdownViewer.app/Resources/Info-gnustep.plist; \
	elif [ -d MarkdownViewer.app/Contents/Resources ]; then \
		info=MarkdownViewer.app/Contents/Resources/Info-gnustep.plist; \
	else \
		echo "error: could not locate the bundle's Resources directory for Info-gnustep.plist" >&2; exit 1; \
	fi; \
	if [ -z "$(OMD_VERSION)" ]; then echo "error: no version: VERSION is missing and OMD_VERSION is unset" >&2; exit 1; fi; \
	cp MarkdownViewerInfo.plist "$$info"; \
	printf '{ ApplicationVersion = "%s"; ApplicationRelease = "%s"; CFBundleShortVersionString = "%s"; CFBundleVersion = "%s"; }\n' \
		"$(OMD_VERSION)" "$(OMD_VERSION)" "$(OMD_VERSION)" "$(OMD_VERSION)" > $(GNUSTEP_OBJ_DIR)/version-info.plist; \
	plmerge "$$info" $(GNUSTEP_OBJ_DIR)/version-info.plist >/dev/null 2>&1 || { echo "error: plmerge failed on $$info" >&2; exit 1; }; \
	grep -q "ApplicationRelease = \"$(OMD_VERSION)\"" "$$info" || { echo "error: $$info lacks ApplicationRelease $(OMD_VERSION)" >&2; exit 1; }
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
