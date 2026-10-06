// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>
#import "OMMarkdownRenderer.h"

// User defaults keys for the viewer's settings.
extern NSString * const OMDSourceEditorFontNameDefaultsKey;
extern NSString * const OMDSourceEditorFontSizeDefaultsKey;
extern NSString * const OMDMathRenderingPolicyDefaultsKey;
extern NSString * const OMDDiagramRenderingPolicyDefaultsKey;
extern NSString * const OMDAllowRemoteImagesDefaultsKey;
extern NSString * const OMDSplitSyncModeDefaultsKey;
extern NSString * const OMDWordSelectionModifierShimDefaultsKey;
extern NSString * const OMDSourceSyntaxHighlightingDefaultsKey;
extern NSString * const OMDSourceHighlightHighContrastDefaultsKey;
extern NSString * const OMDSourceHighlightAccentColorDefaultsKey;
extern NSString * const OMDSourceVimKeyBindingsDefaultsKey;
extern NSString * const OMDRendererSyntaxHighlightingDefaultsKey;
extern NSString * const OMDShowFormattingBarDefaultsKey;
extern NSString * const OMDPreviewFullWidthDefaultsKey;
extern NSString * const OMDLayoutDensityDefaultsKey;
extern NSString * const OMDScrollSpeedDefaultsKey;
extern NSString * const OMDExplorerLocalRootPathDefaultsKey;
extern NSString * const OMDExplorerMaxFileSizeMBDefaultsKey;
extern NSString * const OMDExplorerListFontSizeDefaultsKey;
extern NSString * const OMDExplorerShowHiddenFilesDefaultsKey;
extern NSString * const OMDExplorerSidebarVisibleDefaultsKey;
extern NSString * const OMDOutlineVisibleDefaultsKey;

// How the editor and preview follow each other in Split mode.
typedef NS_ENUM(NSInteger, OMDSplitSyncMode) {
    OMDSplitSyncModeUnlinked = 0,
    OMDSplitSyncModeLinkedScrolling = 1,
    OMDSplitSyncModeCaretSelectionFollow = 2
};

// Range and default of the scroll speed setting.
static const CGFloat OMDScrollSpeedMinimum = 10.0;
static const CGFloat OMDScrollSpeedMaximum = 40.0;
static const CGFloat OMDScrollSpeedDefault = 20.0;

// Stored setting values, with anything unknown mapped to the default.
OMMarkdownDiagramRenderingPolicy OMDDiagramRenderingPolicyFromInteger(NSInteger value);
OMMarkdownMathRenderingPolicy OMDMathRenderingPolicyFromInteger(NSInteger value);
OMDSplitSyncMode OMDSplitSyncModeFromInteger(NSInteger value);

// Removes settings of features that no longer exist.
void OMDRemoveRetiredDefaults(void);
