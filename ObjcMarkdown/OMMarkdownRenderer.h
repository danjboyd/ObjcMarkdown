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

@interface OMMarkdownRenderer : NSObject

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown;
- (instancetype)initWithTheme:(OMTheme *)theme;
- (instancetype)initWithTheme:(OMTheme *)theme parsingOptions:(OMMarkdownParsingOptions *)parsingOptions;
+ (BOOL)isTreeSitterAvailable;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, assign) CGFloat layoutWidth;
@property (nonatomic, assign) BOOL allowTableHorizontalOverflow;
@property (nonatomic, assign) BOOL asynchronousMathGenerationEnabled;
@property (nonatomic, retain) OMMarkdownParsingOptions *parsingOptions;
- (NSColor *)backgroundColor;
@property (nonatomic, readonly) NSArray *codeBlockRanges;
@property (nonatomic, readonly) NSArray *blockquoteRanges;
@property (nonatomic, readonly) NSArray *blockAnchors;

@end
