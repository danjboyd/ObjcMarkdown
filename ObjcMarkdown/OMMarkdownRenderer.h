// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import "OMExport.h"
#import <AppKit/AppKit.h>
#import "OMMarkdownParsingOptions.h"

@class OMTheme;

OM_EXPORT NSString * const OMMarkdownRendererMathArtifactsDidWarmNotification;
OM_EXPORT NSString * const OMMarkdownRendererRemoteImagesDidWarmNotification;
OM_EXPORT NSString * const OMMarkdownRendererAnchorSourceStartLineKey;
OM_EXPORT NSString * const OMMarkdownRendererAnchorSourceEndLineKey;
OM_EXPORT NSString * const OMMarkdownRendererAnchorTargetStartKey;
OM_EXPORT NSString * const OMMarkdownRendererAnchorTargetLengthKey;
OM_EXPORT NSString * const OMMarkdownRendererAnchorBlockIDKey;

// Keys in the dictionaries returned by -headings.
OM_EXPORT NSString * const OMMarkdownRendererHeadingLevelKey;       // NSNumber, 1-6
OM_EXPORT NSString * const OMMarkdownRendererHeadingTitleKey;       // NSString, plain text
OM_EXPORT NSString * const OMMarkdownRendererHeadingAnchorKey;      // NSString, GitHub-style slug
OM_EXPORT NSString * const OMMarkdownRendererHeadingRangeKey;       // NSValue, heading text in the rendered string
OM_EXPORT NSString * const OMMarkdownRendererHeadingSourceLineKey;  // NSNumber, 1-based
// Attribute on each heading's text: its anchor slug (the target of "#slug" links).
OM_EXPORT NSString * const OMMarkdownRendererHeadingAnchorAttributeName;
// Attribute marking a footnote anchor (the target of "#fn-label" and
// "#fnref-label" links): "fn-label" on the note's first character,
// "fnref-label" on its first reference, then "fnref-label-2" ...
OM_EXPORT NSString * const OMMarkdownRendererFootnoteAnchorAttributeName;
// Attribute on a GitHub alert quote ("> [!NOTE]" ...): the NSColor for its bar.
OM_EXPORT NSString * const OMMarkdownRendererBlockquoteColorAttributeName;

// Keys in the dictionaries returned by -diagramBlocks.
OM_EXPORT NSString * const OMMarkdownRendererDiagramRangeKey;
OM_EXPORT NSString * const OMMarkdownRendererDiagramSourceKey;

// The cell of a rendered picture. It draws a copy scaled once to its
// displayed size; -fullImage reads the picture again at full size (for
// copying), or returns the displayed copy if it can't.
@interface OMImageAttachmentCell : NSTextAttachmentCell
{
    NSURL *_sourceURL;
}
- (instancetype)initImageCell:(NSImage *)image sourceURL:(NSURL *)sourceURL;
- (NSImage *)fullImage;
@end

@interface OMMarkdownRenderer : NSObject

// Safe to call from any thread. Rendering touches process-global AppKit text
// state, so calls serialise against every other renderer in the process.
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown;
- (instancetype)initWithTheme:(OMTheme *)theme;
- (instancetype)initWithTheme:(OMTheme *)theme parsingOptions:(OMMarkdownParsingOptions *)parsingOptions;
+ (BOOL)isTreeSitterAvailable;
// Resolved local image dependencies, including files that do not yet exist.
+ (NSArray *)localImageURLsInMarkdown:(NSString *)markdown baseURL:(NSURL *)baseURL;
// Drops every cached render of formula, so the next render runs LaTeX again.
+ (void)invalidateCachedMathForFormula:(NSString *)formula;
// GitHub's anchor slug for a heading title, before de-duplication: lowercase,
// letters/marks/numbers/"_"/"-"/spaces kept, spaces turned into "-".
+ (NSString *)anchorSlugForHeadingTitle:(NSString *)title;
// The headings of markdown as -headings lists them after a render (same
// levels, titles, anchors and source lines), found by parsing only. Their
// range in a rendered string is unknown: {NSNotFound, 0}.
+ (NSArray *)headingsInMarkdown:(NSString *)markdown;
// The colours and fonts rendered with; may be changed between renders.
@property (nonatomic, retain) OMTheme *theme;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, assign) CGFloat layoutWidth;
@property (nonatomic, assign) BOOL allowTableHorizontalOverflow;
@property (nonatomic, assign) BOOL asynchronousMathGenerationEnabled;
@property (nonatomic, retain) OMMarkdownParsingOptions *parsingOptions;
- (NSColor *)backgroundColor;
@property (nonatomic, readonly) NSArray *codeBlockRanges;
@property (nonatomic, readonly) NSArray *blockquoteRanges;
@property (nonatomic, readonly) NSArray *blockAnchors;
// One dictionary per drawn diagram: its range in the rendered string, and the
// mermaid source it was drawn from. Diagrams are deliberately absent from
// -codeBlockRanges so that no code background is painted behind them.
@property (nonatomic, readonly) NSArray *diagramBlocks;
// One dictionary per heading, in document order (keys above). Repeated slugs
// get "-1", "-2" ... as on GitHub.
@property (nonatomic, readonly) NSArray *headings;

@end
