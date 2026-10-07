// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Shared by the OMMarkdownRenderer*.m files; not installed.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import "OMMarkdownRenderer.h"
#import "OMMarkdownParsingOptions.h"
#import "OMAppKitSerialization.h"
#import "OMBlockSignatureIndex.h"
#import "OMRenderedObject.h"
#import "OMTheme.h"
#include "cmark-gfm.h"
#include "cmark-gfm-core-extensions.h"
#include "OMGFMParser.h"
#include "strikethrough.h"
#include "table.h"
#import "OMMermaidERDiagram.h"
#import "OMMermaidERDrawing.h"
#import "OMMermaidFlowchart.h"
#import "OMMermaidFlowchartDrawing.h"
#import "OMStrikethroughLayoutManager.h"
#import "OMTextTable.h"
#include <ctype.h>
#if defined(_WIN32)
#include <windows.h>
#include <gdiplus/gdiplus.h>
#else
#include <dlfcn.h>
#endif
#include <math.h>
#include <stdlib.h>
#include <string.h>

#if defined(__GNUC__) && !defined(_WIN32)
#pragma GCC visibility push(hidden)
#endif

typedef struct {
    NSUInteger mathRequests;
    NSUInteger mathCacheHits;
    NSUInteger mathCacheMisses;
    NSUInteger mathAssetCacheHits;
    NSUInteger mathAssetCacheMisses;
    NSUInteger mathRendered;
    NSUInteger mathFailures;
    NSUInteger latexRuns;
    NSUInteger dvisvgmRuns;
    NSTimeInterval latexSeconds;
    NSTimeInterval dvisvgmSeconds;
    NSTimeInterval svgDecodeSeconds;
    NSTimeInterval mathTotalSeconds;
} OMMathPerfStats;

typedef struct {
    OMMarkdownParsingOptions *parsingOptions;
    NSArray *sourceLines;
    NSMutableArray *blockAnchors;
    NSMutableArray *diagramBlocks;
    NSMutableArray *headings;
    // Slugs handed out so far in this document, for GitHub's de-duplication.
    NSMutableDictionary *headingSlugCounts;
    // The list contexts enclosing the block being rendered (see OMRenderList).
    NSMutableArray *listStack;
    // Hashed source lines for block IDs (see OMBlockSignatureIndex).
    OMBlockSignatureIndex *blockSignatures;
    // One entry per enclosing block quote: YES for a GitHub alert, whose
    // text keeps the normal colour instead of the muted quote colour.
    NSMutableArray *quoteKinds;
    NSMutableArray *consumedDisplayMathLineRanges;
    // Raw source of the current block's formulas, keyed by their unescaped
    // form; see OMPrepareRawMathSources.
    NSMutableDictionary *rawMathSources;
    OMMathPerfStats *mathPerfStats;
    CGFloat layoutWidth;
    BOOL allowTableHorizontalOverflow;
    BOOL asynchronousMathGenerationEnabled;
} OMRenderContext;

// OMMarkdownRenderer.m
void OMAppendAttributedSegment(NSMutableAttributedString *output,
                               NSAttributedString *segment);
void OMAppendInlineTextFromNode(cmark_node *node, NSMutableString *buffer);
extern NSString * const OMHardLineBreakAttributeName;
BOOL OMShouldRenderImages(const OMRenderContext *renderContext);
NSDictionary *OMHeadingAttributesForLevel(OMTheme *theme, NSUInteger level, CGFloat scale);
void OMRenderHTMLThematicBreak(OMTheme *theme,
                               NSMutableAttributedString *output,
                               NSMutableDictionary *attributes,
                               CGFloat layoutWidth);
void OMAppendString(NSMutableAttributedString *output,
                    NSString *string,
                    NSDictionary *attributes);
BOOL OMExternalMathRenderingEnabled(const OMRenderContext *renderContext);
NSTimeInterval OMExternalToolTimeout(const OMRenderContext *renderContext);
NSFont *OMFontWithTraits(NSFont *font, NSFontTraitMask traits);
NSString *OMInlinePlainText(cmark_node *node);
BOOL OMIsTightList(NSMutableArray *listStack);
CGFloat OMListContentIndent(const OMRenderContext *renderContext, CGFloat scale);
BOOL OMMarkerIsEscaped(NSString *text, NSUInteger location);
NSUInteger OMMathMaximumFormulaLength(const OMRenderContext *renderContext);
BOOL OMNativeDiagramRenderingEnabled(const OMRenderContext *renderContext);
NSTimeInterval OMNow(void);
NSMutableParagraphStyle *OMParagraphStyleWithIndent(CGFloat firstIndent,
                                                    CGFloat headIndent,
                                                    CGFloat spacingAfter,
                                                    CGFloat lineSpacing,
                                                    CGFloat lineHeightMultiple,
                                                    CGFloat fontSize);
OMMarkdownParsingOptions *OMRenderContextParsingOptions(const OMRenderContext *renderContext);
void OMRenderInlines(cmark_node *node,
                     OMTheme *theme,
                     NSMutableAttributedString *output,
                     NSMutableDictionary *attributes,
                     CGFloat scale,
                     const OMRenderContext *renderContext);
BOOL OMShouldAllowRemoteImages(const OMRenderContext *renderContext);
BOOL OMShouldApplyCodeSyntaxHighlighting(const OMRenderContext *renderContext);
BOOL OMShouldParseMathSpans(const OMRenderContext *renderContext);
BOOL OMURLUsesAllowedImageScheme(NSURL *url);
BOOL OMURLUsesAllowedLinkScheme(NSURL *url);

// OMMarkdownRendererSource.m
NSString *OMCommonMarkUnescaped(NSString *text);
NSString *OMImageMarkdownForNode(cmark_node *imageNode);
NSString *OMMarkdownByBlankingFrontMatter(NSString *markdown);
BOOL OMNodeLineBounds(cmark_node *node, NSUInteger *startLineOut, NSUInteger *endLineOut);
void OMRecordBlockAnchor(cmark_node *node,
                         NSUInteger targetStart,
                         NSUInteger targetEnd,
                         const OMRenderContext *renderContext);
void OMRecordBlockAnchorForSourceRange(cmark_node *node,
                                       NSUInteger sourceStartLine,
                                       NSUInteger sourceEndLine,
                                       NSUInteger targetStart,
                                       NSUInteger targetEnd,
                                       const OMRenderContext *renderContext);
void OMResolvePendingRenderedObjects(NSMutableAttributedString *output,
                                     NSArray *blockAnchors,
                                     NSString *markdown);
NSString *OMSourceFragmentForNode(cmark_node *node, NSArray *sourceLines);
NSArray *OMSourceLinesForMarkdown(NSString *markdown);
NSString *OMSourceTextForNodeLines(cmark_node *node, const OMRenderContext *renderContext);
void OMTagAppendedObject(NSMutableAttributedString *output,
                         NSUInteger start,
                         OMRenderedObjectKind kind,
                         NSString *source,
                         NSString *markdown);

// OMMarkdownRendererCode.m
void OMApplyCodeSyntaxHighlighting(cmark_node *codeBlockNode,
                                   NSMutableAttributedString *codeSegment,
                                   NSColor *backgroundColor,
                                   const OMRenderContext *renderContext);
BOOL OMColorRGBA(NSColor *color, CGFloat *red, CGFloat *green, CGFloat *blue, CGFloat *alpha);
NSString *OMPrimaryFenceToken(cmark_node *codeBlockNode);

// OMMarkdownRendererImages.m
NSString *OMFallbackImageTextForNode(cmark_node *imageNode);
NSAttributedString *OMImageAttachmentAttributedString(cmark_node *imageNode,
                                                      NSMutableDictionary *attributes,
                                                      CGFloat scale,
                                                      const OMRenderContext *renderContext);
NSAttributedString *OMAttributedStringFittingImagesToWidth(NSAttributedString *string, CGFloat width);
NSAttributedString *OMImageAttachmentForURLString(NSString *urlString,
                                                  NSMutableDictionary *attributes,
                                                  CGFloat scale,
                                                  const OMRenderContext *renderContext);
NSURL *OMResolvedImageURL(NSString *urlString,
                          const OMRenderContext *renderContext);
NSURL *OMResolvedLinkURL(NSString *urlString,
                         const OMRenderContext *renderContext);
BOOL OMURLUsesRemoteScheme(NSURL *url);

// OMMarkdownRendererMath.m
void OMAppendDisplayMathFormula(NSString *formula,
                                OMTheme *theme,
                                NSMutableAttributedString *output,
                                NSMutableDictionary *attributes,
                                CGFloat scale,
                                const OMRenderContext *renderContext);
BOOL OMCharacterIsDigit(unichar ch);
BOOL OMCharacterIsWhitespaceOrNewline(unichar ch);
BOOL OMDisplayMathLineAlreadyConsumed(NSUInteger lineNumber,
                                      const OMRenderContext *renderContext);
BOOL OMDollarIsEscaped(NSString *text, NSUInteger location);
NSString *OMDviPngExecutablePath(void);
NSString *OMExecutablePathNamed(NSString *name);
NSString *OMLaTeXExecutablePath(void);
NSAttributedString *OMMathAttachmentAttributedString(NSString *formula,
                                                     OMTheme *theme,
                                                     NSMutableDictionary *attributes,
                                                     CGFloat scale,
                                                     BOOL displayMath,
                                                     const OMRenderContext *renderContext);
NSDictionary *OMMathAttributes(OMTheme *theme,
                               NSMutableDictionary *attributes,
                               CGFloat scale,
                               BOOL displayMath);
NSMutableDictionary *OMMathFormulaGenerations(void);
NSString *OMPlainTexExecutablePath(void);
void OMPrepareRawMathSources(cmark_node *node, const OMRenderContext *renderContext);
NSString *OMRawMathFormula(NSString *formula, BOOL display, const OMRenderContext *renderContext);
NSString *OMReadableMathFallbackString(NSString *formula);
cmark_node *OMTryAppendMultiNodeDisplayMath(cmark_node *startNode,
                                            OMTheme *theme,
                                            NSMutableAttributedString *output,
                                            NSMutableDictionary *attributes,
                                            CGFloat scale,
                                            BOOL *didRender,
                                            const OMRenderContext *renderContext);
BOOL OMTryRenderRawDisplayMathBlock(cmark_node *node,
                                    OMTheme *theme,
                                    NSMutableAttributedString *output,
                                    NSMutableDictionary *attributes,
                                    NSMutableArray *listStack,
                                    CGFloat scale,
                                    const OMRenderContext *renderContext);

// OMMarkdownRendererTables.m
NSColor *OMPipeTableBodyBackgroundColorForTheme(OMTheme *theme);
NSColor *OMPipeTableBorderColorForTheme(OMTheme *theme);
NSColor *OMPipeTableHeaderBackgroundColorForTheme(OMTheme *theme);
void OMRenderGFMTable(cmark_node *node,
                      OMTheme *theme,
                      NSMutableAttributedString *output,
                      NSMutableDictionary *attributes,
                      NSMutableArray *listStack,
                      NSUInteger quoteLevel,
                      CGFloat scale,
                      CGFloat layoutWidth,
                      const OMRenderContext *renderContext);
NSString *OMTrimmedCellText(NSString *value);

// OMMarkdownRendererMermaid.m
void OMAppendMermaidDiagnostic(NSString *diagnostic,
                               OMTheme *theme,
                               NSMutableAttributedString *output,
                               NSDictionary *blockAttributes,
                               CGFloat indent,
                               CGFloat codeFontSize,
                               CGFloat scale);
BOOL OMTryRenderMermaidDiagram(cmark_node *node,
                               NSString *code,
                               OMTheme *theme,
                               NSMutableAttributedString *output,
                               NSMutableDictionary *attributes,
                               NSUInteger quoteLevel,
                               CGFloat scale,
                               const OMRenderContext *renderContext,
                               NSString **diagnosticOut);

// OMMarkdownRendererHTML.m
extern NSString * const OMHTMLStyleStackAttributeName;
NSString *OMHTMLDecodeEntities(NSString *text);
void OMAppendSafeInlineHTML(NSString *html,
                            NSMutableAttributedString *output,
                            NSMutableDictionary *attributes,
                            OMTheme *theme,
                            CGFloat scale,
                            const OMRenderContext *renderContext);
void OMAppendSafeBlockHTML(NSString *html,
                           NSMutableAttributedString *output,
                           NSMutableDictionary *blockAttributes,
                           OMTheme *theme,
                           CGFloat scale,
                           const OMRenderContext *renderContext);

#if defined(__GNUC__) && !defined(_WIN32)
#pragma GCC visibility pop
#endif
