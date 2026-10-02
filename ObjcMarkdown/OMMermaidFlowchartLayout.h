// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>

@class OMMermaidFlowchart;
@class OMMermaidFlowNode;
@class OMMermaidFlowEdge;

// Geometry is in diagram coordinates: origin top left, y growing down.

// Text sizes come from the caller, keeping layout free of AppKit font metrics.
@protocol OMMermaidFlowTextMeasuring <NSObject>
// label may hold several lines separated by "\n".
- (NSSize)mermaidFlowSizeForNodeLabel:(NSString *)label;
- (NSSize)mermaidFlowSizeForEdgeLabel:(NSString *)label;
@end

@interface OMMermaidFlowNodeLayout : NSObject
{
    OMMermaidFlowNode *_node;
    NSString *_text;
    NSRect _frame;
}
@property (nonatomic, readonly) OMMermaidFlowNode *node;
// The label with "<br>" turned into line breaks.
@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) NSRect frame;
@end

@interface OMMermaidFlowEdgeLayout : NSObject
{
    OMMermaidFlowEdge *_edge;
    NSArray *_points;
    NSRect _labelFrame;
}
@property (nonatomic, readonly) OMMermaidFlowEdge *edge;
// NSValue points, from the source node's outline to the target's.
@property (nonatomic, readonly) NSArray *points;
// NSZeroRect when the edge has no label.
@property (nonatomic, readonly) NSRect labelFrame;
@end

@interface OMMermaidFlowchartLayout : NSObject
{
    NSArray *_nodeLayouts;
    NSArray *_edgeLayouts;
    NSSize _size;
}

+ (instancetype)layoutForFlowchart:(OMMermaidFlowchart *)flowchart
                          measurer:(id<OMMermaidFlowTextMeasuring>)measurer;

@property (nonatomic, readonly) NSArray *nodeLayouts;
@property (nonatomic, readonly) NSArray *edgeLayouts;
@property (nonatomic, readonly) NSSize size;

- (OMMermaidFlowNodeLayout *)layoutForNodeIdentifier:(NSString *)identifier;

@end

// "<br>", "<br/>" and "<br />" as line breaks.
FOUNDATION_EXPORT NSString *OMMermaidFlowDisplayText(NSString *label);
