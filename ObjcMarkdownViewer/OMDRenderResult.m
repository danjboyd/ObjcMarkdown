// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRenderResult.h"
#import "OMMarkdownRenderer.h"

@implementation OMDRenderResult

@synthesize markdown = _markdown;
@synthesize blockAnchors = _blockAnchors;
@synthesize codeBlockRanges = _codeBlockRanges;
@synthesize blockquoteRanges = _blockquoteRanges;
@synthesize diagramBlocks = _diagramBlocks;
@synthesize headings = _headings;
@synthesize taskItems = _taskItems;
@synthesize sourceBlockDescriptors = _sourceBlockDescriptors;
@synthesize zoomScale = _zoomScale;
@synthesize layoutWidth = _layoutWidth;
@synthesize sourceRevision = _sourceRevision;

+ (instancetype)resultOfRenderer:(OMMarkdownRenderer *)renderer
                        markdown:(NSString *)markdown
                  sourceRevision:(NSUInteger)sourceRevision
{
    OMDRenderResult *result = [[[self alloc] init] autorelease];
    if (result == nil || renderer == nil) {
        return result;
    }
    result->_markdown = [markdown copy];
    result->_blockAnchors = [[renderer blockAnchors] copy];
    result->_codeBlockRanges = [[renderer codeBlockRanges] copy];
    result->_blockquoteRanges = [[renderer blockquoteRanges] copy];
    result->_diagramBlocks = [[renderer diagramBlocks] copy];
    result->_headings = [[renderer headings] copy];
    result->_taskItems = [[renderer taskItems] copy];
    if ([renderer respondsToSelector:@selector(sourceBlockDescriptors)]) {
        result->_sourceBlockDescriptors = [[renderer performSelector:@selector(sourceBlockDescriptors)] copy];
    }
    result->_zoomScale = [renderer zoomScale];
    result->_layoutWidth = [renderer layoutWidth];
    result->_sourceRevision = sourceRevision;
    return result;
}

- (void)dealloc
{
    [_markdown release];
    [_blockAnchors release];
    [_codeBlockRanges release];
    [_blockquoteRanges release];
    [_diagramBlocks release];
    [_headings release];
    [_taskItems release];
    [_sourceBlockDescriptors release];
    [super dealloc];
}

@end
