// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <AppKit/AppKit.h>
#import "OMExport.h"
#import "OMMermaidFlowchartLayout.h"

@class OMMermaidFlowchart;
@class OMMermaidERDrawingStyle;

// Measures labels with a style's fonts (nodes: attributeFont, edges: labelFont).
@interface OMMermaidFlowStyleMeasurer : NSObject <OMMermaidFlowTextMeasuring>
{
    OMMermaidERDrawingStyle *_style;
}
- (instancetype)initWithStyle:(OMMermaidERDrawingStyle *)style;
@end

// Draws a laid-out flowchart; shares the erDiagram drawing style.
@interface OMMermaidFlowchartAttachmentCell : NSTextAttachmentCell
{
    OMMermaidFlowchartLayout *_layout;
    OMMermaidERDrawingStyle *_style;
    CGFloat _drawScale;
}

- (instancetype)initWithLayout:(OMMermaidFlowchartLayout *)layout
                         style:(OMMermaidERDrawingStyle *)style
                     drawScale:(CGFloat)drawScale;

@property (nonatomic, readonly) OMMermaidFlowchartLayout *layout;
@property (nonatomic, readonly) CGFloat drawScale;

@end

// A one-character attributed string carrying the drawn flowchart, scaled
// down to maximumWidth if needed (zero or less: no limit), or nil.
OM_EXPORT NSAttributedString *OMMermaidFlowchartAttachmentAttributedString(OMMermaidFlowchart *flowchart,
                                                                           OMMermaidERDrawingStyle *style,
                                                                           CGFloat maximumWidth,
                                                                           NSDictionary *attributes);
