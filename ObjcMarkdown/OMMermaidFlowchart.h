// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>

// A Mermaid flowchart ("flowchart TD" / "graph LR"), parsed for native drawing.
// Supported: the five directions; node shapes [ ], ( ), ([ ]), (( )), { }, [[ ]]
// (others draw as rectangles); links -->, ---, -.->, -.-, ==>, ===, with
// "-- text -->" and "-->|text|" labels; chains (A --> B --> C) and "&" groups.
// subgraph/end, classDef, class, style, linkStyle, click and direction lines
// are skipped (their nodes and links still draw, without grouping or styling).

FOUNDATION_EXPORT NSString * const OMMermaidFlowchartErrorDomain;
// NSNumber, 1-based line in the diagram source.
FOUNDATION_EXPORT NSString * const OMMermaidFlowchartErrorLineNumberKey;

typedef NS_ENUM(NSInteger, OMMermaidFlowDirection) {
    OMMermaidFlowDirectionTopDown = 0,
    OMMermaidFlowDirectionBottomUp = 1,
    OMMermaidFlowDirectionLeftRight = 2,
    OMMermaidFlowDirectionRightLeft = 3
};

typedef NS_ENUM(NSInteger, OMMermaidFlowNodeShape) {
    OMMermaidFlowNodeShapeRectangle = 0,
    OMMermaidFlowNodeShapeRounded = 1,
    OMMermaidFlowNodeShapeStadium = 2,
    OMMermaidFlowNodeShapeCircle = 3,
    OMMermaidFlowNodeShapeDiamond = 4,
    OMMermaidFlowNodeShapeSubroutine = 5
};

typedef NS_ENUM(NSInteger, OMMermaidFlowEdgeStyle) {
    OMMermaidFlowEdgeStyleSolid = 0,
    OMMermaidFlowEdgeStyleDotted = 1,
    OMMermaidFlowEdgeStyleThick = 2
};

@interface OMMermaidFlowNode : NSObject
{
    NSString *_identifier;
    NSString *_label;
    OMMermaidFlowNodeShape _shape;
}
@property (nonatomic, readonly) NSString *identifier;
// Display text; lines split on "<br>".
@property (nonatomic, readonly) NSString *label;
@property (nonatomic, readonly) OMMermaidFlowNodeShape shape;
@end

@interface OMMermaidFlowEdge : NSObject
{
    NSString *_fromIdentifier;
    NSString *_toIdentifier;
    NSString *_label;
    OMMermaidFlowEdgeStyle _style;
    BOOL _hasArrow;
}
@property (nonatomic, readonly) NSString *fromIdentifier;
@property (nonatomic, readonly) NSString *toIdentifier;
// nil when unlabelled.
@property (nonatomic, readonly) NSString *label;
@property (nonatomic, readonly) OMMermaidFlowEdgeStyle style;
@property (nonatomic, readonly) BOOL hasArrow;
@end

@interface OMMermaidFlowchart : NSObject
{
    OMMermaidFlowDirection _direction;
    NSArray *_nodes;
    NSArray *_edges;
    NSUInteger _skippedStatementCount;
}

// YES when the first meaningful line starts with "flowchart" or "graph".
+ (BOOL)sourceDeclaresFlowchart:(NSString *)source;
+ (instancetype)flowchartWithSource:(NSString *)source error:(NSError **)error;

@property (nonatomic, readonly) OMMermaidFlowDirection direction;
// In order of first mention.
@property (nonatomic, readonly) NSArray *nodes;
@property (nonatomic, readonly) NSArray *edges;
// subgraph/style/... lines that were skipped.
@property (nonatomic, readonly) NSUInteger skippedStatementCount;

- (OMMermaidFlowNode *)nodeWithIdentifier:(NSString *)identifier;

@end

// The diagram type a Mermaid source declares ("flowchart", "sequenceDiagram"...),
// from its first meaningful line, or nil.
FOUNDATION_EXPORT NSString *OMMermaidDeclaredDiagramType(NSString *source);
