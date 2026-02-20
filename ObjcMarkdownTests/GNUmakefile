include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ObjcMarkdownTests

ObjcMarkdownTests_OBJC_FILES = OMMarkdownRendererTests.m OMDDocumentConverterTests.m OMDPreviewSyncTests.m OMDSourceHighlighterTests.m OMDViewerModeStateTests.m OMDSourceTextViewTests.m OMDSourceTextViewStructuredNewlineTests.m OMDLineNumberRulerViewTests.m OMDInlineToggleTests.m ../ObjcMarkdownViewer/OMDDocumentConverter.m ../ObjcMarkdownViewer/OMDPandocConverter.m ../ObjcMarkdownViewer/OMDPreviewSync.m ../ObjcMarkdownViewer/OMDSourceHighlighter.m ../ObjcMarkdownViewer/OMDViewerModeState.m ../ObjcMarkdownViewer/OMDSourceTextView.m ../ObjcMarkdownViewer/OMDLineNumberRulerView.m ../ObjcMarkdownViewer/OMDInlineToggle.m
ObjcMarkdownTests_CPPFLAGS += -I../ObjcMarkdown
ObjcMarkdownTests_CPPFLAGS += -I../ObjcMarkdownViewer
ObjcMarkdownTests_LDFLAGS += -L../ObjcMarkdown/$(GNUSTEP_OBJ_DIR)
ObjcMarkdownTests_BUNDLE_LIBS += -lObjcMarkdown -lXCTest -ldispatch -lcmark

include $(GNUSTEP_MAKEFILES)/bundle.make
