// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDViewerDefaults.h"

NSString * const OMDSourceEditorFontNameDefaultsKey = @"ObjcMarkdownSourceEditorFontName";
NSString * const OMDSourceEditorFontSizeDefaultsKey = @"ObjcMarkdownSourceEditorFontSize";
NSString * const OMDMathRenderingPolicyDefaultsKey = @"ObjcMarkdownMathRenderingPolicy";
NSString * const OMDDiagramRenderingPolicyDefaultsKey = @"ObjcMarkdownDiagramRenderingPolicy";
NSString * const OMDAllowRemoteImagesDefaultsKey = @"ObjcMarkdownAllowRemoteImages";
NSString * const OMDSplitSyncModeDefaultsKey = @"ObjcMarkdownSplitSyncMode";
NSString * const OMDWordSelectionModifierShimDefaultsKey = @"ObjcMarkdownWordSelectionShimEnabled";
NSString * const OMDSourceSyntaxHighlightingDefaultsKey = @"ObjcMarkdownSourceSyntaxHighlightingEnabled";
NSString * const OMDSourceHighlightHighContrastDefaultsKey = @"ObjcMarkdownSourceHighlightHighContrastEnabled";
NSString * const OMDSourceHighlightAccentColorDefaultsKey = @"ObjcMarkdownSourceHighlightAccentColor";
NSString * const OMDSourceVimKeyBindingsDefaultsKey = @"ObjcMarkdownSourceVimKeyBindingsEnabled";
NSString * const OMDRendererSyntaxHighlightingDefaultsKey = @"ObjcMarkdownRendererSyntaxHighlightingEnabled";
NSString * const OMDShowFormattingBarDefaultsKey = @"ObjcMarkdownShowFormattingBar";
NSString * const OMDPreviewFullWidthDefaultsKey = @"ObjcMarkdownPreviewFullWidth";
NSString * const OMDLayoutDensityDefaultsKey = @"ObjcMarkdownLayoutDensityMode";
NSString * const OMDScrollSpeedDefaultsKey = @"ObjcMarkdownScrollSpeed";
NSString * const OMDExplorerLocalRootPathDefaultsKey = @"ObjcMarkdownExplorerLocalRootPath";
NSString * const OMDExplorerMaxFileSizeMBDefaultsKey = @"ObjcMarkdownExplorerMaxFileSizeMB";
NSString * const OMDExplorerListFontSizeDefaultsKey = @"ObjcMarkdownExplorerListFontSize";
NSString * const OMDExplorerShowHiddenFilesDefaultsKey = @"ObjcMarkdownExplorerShowHiddenFiles";
NSString * const OMDExplorerSidebarVisibleDefaultsKey = @"ObjcMarkdownExplorerSidebarVisible";
NSString * const OMDOutlineVisibleDefaultsKey = @"ObjcMarkdownOutlineVisible";

OMMarkdownDiagramRenderingPolicy OMDDiagramRenderingPolicyFromInteger(NSInteger value)
{
    if (value == OMMarkdownDiagramRenderingPolicySourceCode) {
        return OMMarkdownDiagramRenderingPolicySourceCode;
    }
    return OMMarkdownDiagramRenderingPolicyNative;
}

OMMarkdownMathRenderingPolicy OMDMathRenderingPolicyFromInteger(NSInteger value)
{
    if (value == OMMarkdownMathRenderingPolicyDisabled) {
        return OMMarkdownMathRenderingPolicyDisabled;
    }
    if (value == OMMarkdownMathRenderingPolicyExternalTools) {
        return OMMarkdownMathRenderingPolicyExternalTools;
    }
    return OMMarkdownMathRenderingPolicyStyledText;
}

OMDSplitSyncMode OMDSplitSyncModeFromInteger(NSInteger value)
{
    if (value == OMDSplitSyncModeUnlinked) {
        return OMDSplitSyncModeUnlinked;
    }
    if (value == OMDSplitSyncModeCaretSelectionFollow) {
        return OMDSplitSyncModeCaretSelectionFollow;
    }
    return OMDSplitSyncModeLinkedScrolling;
}

void OMDRemoveRetiredDefaults(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // The GitHub explorer mode's settings (#46). The token is a secret, so
    // it shouldn't outlive the feature.
    NSArray *keys = [NSArray arrayWithObjects:@"ObjcMarkdownGitHubToken",
                                              @"ObjcMarkdownExplorerIncludeForkArchived",
                                              nil];
    for (NSString *key in keys) {
        if ([defaults objectForKey:key] != nil) {
            [defaults removeObjectForKey:key];
        }
    }
}
