// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDViewerModeState.h"
#import "OMMarkdownParsingOptions.h"
#import "OMTheme.h"

@interface OMDViewerModeStateTests : XCTestCase
@end

@implementation OMDViewerModeStateTests

- (void)testPaneLayoutForReadMode
{
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode(OMDViewerModeRead);
    XCTAssertTrue(layout.previewVisible);
    XCTAssertFalse(layout.sourceVisible);
    XCTAssertFalse(layout.splitVisible);
}

- (void)testPaneLayoutForEditMode
{
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode(OMDViewerModeEdit);
    XCTAssertFalse(layout.previewVisible);
    XCTAssertTrue(layout.sourceVisible);
    XCTAssertFalse(layout.splitVisible);
}

- (void)testPaneLayoutForSplitMode
{
    OMDViewerPaneLayout layout = OMDViewerPaneLayoutForMode(OMDViewerModeSplit);
    XCTAssertTrue(layout.previewVisible);
    XCTAssertTrue(layout.sourceVisible);
    XCTAssertTrue(layout.splitVisible);
}

- (void)testPreviewStatusTextForHiddenAndUpdatingAndStale
{
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeEdit, NO, 0, 0) isEqualToString:@"Preview Hidden"]);
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeRead, YES, 0, 0) isEqualToString:@"Preview Updating"]);
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeSplit, NO, 8, 7) isEqualToString:@"Preview Stale"]);
    XCTAssertTrue([OMDPreviewStatusTextForState(OMDViewerModeSplit, NO, 8, 8) isEqualToString:@"Preview Live"]);
}

// The same options and theme, so each test below changes one input.
static BOOL OMDCurrentWith(BOOL stale, NSUInteger revision, CGFloat width, CGFloat zoom,
                           OMMarkdownParsingOptions *options, id theme,
                           OMMarkdownParsingOptions *renderedOptions, id renderedTheme)
{
    return OMDPreviewRenderIsCurrent(stale, 3, revision, 800.0, width, 1.0, zoom,
                                     renderedOptions, options, renderedTheme, theme);
}

- (void)testPreviewRenderIsCurrentOnlyWhenNothingChanged
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    OMTheme *theme = [OMTheme defaultTheme];
    OMTheme *otherTheme = [OMTheme defaultThemeForDarkAppearance:YES];
    OMMarkdownParsingOptions *rendered = [[options copy] autorelease];

    XCTAssertTrue(OMDCurrentWith(NO, 3, 800.0, 1.0, options, theme, rendered, theme));
    XCTAssertTrue(OMDCurrentWith(NO, 3, 800.2, 1.0, options, theme, rendered, theme));
    // A render was asked for, or an artifact arrived, while hidden.
    XCTAssertFalse(OMDCurrentWith(YES, 3, 800.0, 1.0, options, theme, rendered, theme));
    // The source changed, or was reloaded from disk.
    XCTAssertFalse(OMDCurrentWith(NO, 4, 800.0, 1.0, options, theme, rendered, theme));
    XCTAssertFalse(OMDCurrentWith(NO, 3, 400.0, 1.0, options, theme, rendered, theme));
    XCTAssertFalse(OMDCurrentWith(NO, 3, 800.0, 1.25, options, theme, rendered, theme));
    XCTAssertFalse(OMDCurrentWith(NO, 3, 800.0, 1.0, options, otherTheme, rendered, theme));
    // Never rendered: no options kept, and a width of -1.
    XCTAssertFalse(OMDCurrentWith(NO, 3, 800.0, 1.0, options, theme, nil, theme));
    XCTAssertFalse(OMDPreviewRenderIsCurrent(NO, 3, 3, -1.0, -1.0, 1.0, 1.0, rendered, options, theme, theme));
}

- (void)testEveryParsingOptionMakesTheRenderOld
{
    OMMarkdownParsingOptions *base = [OMMarkdownParsingOptions defaultOptions];
    XCTAssertTrue(OMDParsingOptionsEquivalent(base, [[base copy] autorelease]));

    OMMarkdownParsingOptions *changed = [[base copy] autorelease];
    [changed setCmarkOptions:[base cmarkOptions] + 1];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"cmark options");
    changed = [[base copy] autorelease];
    [changed setBaseURL:[NSURL fileURLWithPath:@"/somewhere/else/" isDirectory:YES]];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"base URL, as after Save As");
    changed = [[base copy] autorelease];
    [changed setInlineHTMLPolicy:[base inlineHTMLPolicy] + 1];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"inline HTML");
    changed = [[base copy] autorelease];
    [changed setBlockHTMLPolicy:[base blockHTMLPolicy] + 1];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"block HTML");
    changed = [[base copy] autorelease];
    [changed setRenderImages:![base renderImages]];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"images");
    changed = [[base copy] autorelease];
    [changed setAllowRemoteImages:![base allowRemoteImages]];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"remote images");
    changed = [[base copy] autorelease];
    [changed setCodeSyntaxHighlightingEnabled:![base codeSyntaxHighlightingEnabled]];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"code highlighting");
    changed = [[base copy] autorelease];
    [changed setMathRenderingPolicy:[base mathRenderingPolicy] + 1];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"math rendering");
    changed = [[base copy] autorelease];
    [changed setMaximumMathFormulaLength:[base maximumMathFormulaLength] + 1];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"math length");
    changed = [[base copy] autorelease];
    [changed setExternalToolTimeout:[base externalToolTimeout] + 1.0];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"tool timeout");
    changed = [[base copy] autorelease];
    [changed setDiagramRenderingPolicy:[base diagramRenderingPolicy] + 1];
    XCTAssertFalse(OMDParsingOptionsEquivalent(base, changed), @"diagrams");
}

@end
