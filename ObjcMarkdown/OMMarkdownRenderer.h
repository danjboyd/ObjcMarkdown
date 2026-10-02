// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "OMMarkdownParsingOptions.h"

@class OMTheme;

FOUNDATION_EXPORT NSString * const OMMarkdownRendererMathArtifactsDidWarmNotification;
FOUNDATION_EXPORT NSString * const OMMarkdownRendererRemoteImagesDidWarmNotification;
FOUNDATION_EXPORT NSString * const OMMarkdownRendererAnchorSourceStartLineKey;
FOUNDATION_EXPORT NSString * const OMMarkdownRendererAnchorSourceEndLineKey;
FOUNDATION_EXPORT NSString * const OMMarkdownRendererAnchorTargetStartKey;
FOUNDATION_EXPORT NSString * const OMMarkdownRendererAnchorTargetLengthKey;
FOUNDATION_EXPORT NSString * const OMMarkdownRendererAnchorBlockIDKey;

// Keys in the dictionaries returned by -diagramBlocks.
FOUNDATION_EXPORT NSString * const OMMarkdownRendererDiagramRangeKey;
FOUNDATION_EXPORT NSString * const OMMarkdownRendererDiagramSourceKey;

@interface OMMarkdownRenderer : NSObject

// Safe to call from any thread. Rendering touches process-global AppKit text
// state, so calls serialise against every other renderer in the process.
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown;
- (instancetype)initWithTheme:(OMTheme *)theme;
- (instancetype)initWithTheme:(OMTheme *)theme parsingOptions:(OMMarkdownParsingOptions *)parsingOptions;
+ (BOOL)isTreeSitterAvailable;
// Resolved local image dependencies, including files that do not yet exist.
+ (NSArray *)localImageURLsInMarkdown:(NSString *)markdown baseURL:(NSURL *)baseURL;
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

@end
