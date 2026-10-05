include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ObjcMarkdownTests

ObjcMarkdownTests_OBJC_FILES = OMMarkdownRendererTests.m OMMermaidERDiagramTests.m OMMermaidERLayoutTests.m OMDDocumentConverterTests.m OMDPreviewSyncTests.m OMDSourceHighlighterTests.m OMDViewerModeStateTests.m OMDSourceTextViewTests.m OMDSourceTextViewStructuredNewlineTests.m OMDLineNumberRulerViewTests.m OMDInlineToggleTests.m OMDPanelSelectionTests.m OMDTextViewTests.m OMDOutlineControllerTests.m OMBlockSignatureIndexTests.m OMMermaidFlowchartTests.m OMSpecConformanceTests.m OMDTextFileSupportTests.m ../ObjcMarkdownViewer/OMDDocumentConverter.m ../ObjcMarkdownViewer/OMDPandocConverter.m ../ObjcMarkdownViewer/OMDPreviewSync.m ../ObjcMarkdownViewer/OMDSourceHighlighter.m ../ObjcMarkdownViewer/OMDViewerModeState.m ../ObjcMarkdownViewer/OMDSourceTextView.m ../ObjcMarkdownViewer/OMDLineNumberRulerView.m ../ObjcMarkdownViewer/OMDInlineToggle.m ../ObjcMarkdownViewer/OMDPanelSelection.m ../ObjcMarkdownViewer/OMDTextView.m ../ObjcMarkdownViewer/OMDOutlineController.m ../ObjcMarkdownViewer/OMDTextFileSupport.m
ObjcMarkdownTests_CPPFLAGS += -I../ObjcMarkdown
ObjcMarkdownTests_CPPFLAGS += -I../ObjcMarkdownViewer
ObjcMarkdownTests_CPPFLAGS += -DOM_SPEC_DIR=\"$(CURDIR)/Spec\"
ObjcMarkdownTests_CPPFLAGS += -I../third_party/cmark-gfm/compat -I../third_party/cmark-gfm/src -I../third_party/cmark-gfm/extensions -DCMARK_GFM_STATIC_DEFINE
ifneq (,$(findstring mingw,$(GNUSTEP_HOST_OS)))
ObjcMarkdownTests_OBJCFLAGS += -include sys/types.h "-Dmode_t=unsigned short"
endif
ObjcMarkdownTests_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR)
ObjcMarkdownTests_BUNDLE_LIBS += -lObjcMarkdown -lXCTest -ldispatch

include $(GNUSTEP_MAKEFILES)/bundle.make
