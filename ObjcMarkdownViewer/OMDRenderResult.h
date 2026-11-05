// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

@class OMMarkdownRenderer;

// What one render of the preview produced, kept apart from the renderer
// that produced it (#346): the viewer reads the preview's anchors, ranges,
// headings and task items from the result it applied, so a later render
// (one day on another thread) can't change them under it. Immutable.
@interface OMDRenderResult : NSObject
{
    NSString *_markdown;
    NSArray *_blockAnchors;
    NSArray *_codeBlockRanges;
    NSArray *_blockquoteRanges;
    NSArray *_diagramBlocks;
    NSArray *_headings;
    NSArray *_taskItems;
    NSArray *_sourceBlockDescriptors;
    double _zoomScale;
    double _layoutWidth;
    NSUInteger _sourceRevision;
}

// The outputs of renderer's last render, of markdown, for sourceRevision.
+ (instancetype)resultOfRenderer:(OMMarkdownRenderer *)renderer
                        markdown:(NSString *)markdown
                  sourceRevision:(NSUInteger)sourceRevision;

@property (nonatomic, readonly, copy) NSString *markdown;
@property (nonatomic, readonly, copy) NSArray *blockAnchors;
@property (nonatomic, readonly, copy) NSArray *codeBlockRanges;
@property (nonatomic, readonly, copy) NSArray *blockquoteRanges;
@property (nonatomic, readonly, copy) NSArray *diagramBlocks;
@property (nonatomic, readonly, copy) NSArray *headings;
@property (nonatomic, readonly, copy) NSArray *taskItems;
@property (nonatomic, readonly, copy) NSArray *sourceBlockDescriptors;
@property (nonatomic, readonly) double zoomScale;
@property (nonatomic, readonly) double layoutWidth;
@property (nonatomic, readonly) NSUInteger sourceRevision;

@end
