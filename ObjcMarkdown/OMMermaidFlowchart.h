// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import "OMExport.h"

// A Mermaid flowchart ("flowchart TD" / "graph LR"), parsed for native drawing.
// Supported: the five directions; node shapes [ ], ( ), ([ ]), (( )), { }, [[ ]]
// (others draw as rectangles); links -->, ---, -.->, -.-, ==>, ===, with
// "-- text -->" and "-->|text|" labels; chains (A --> B --> C) and "&" groups;
// subgraph ... end (nested; links to a subgraph end at its frame); classDef,
// class, ":::class" and style (fill, stroke, color, stroke-width,
// stroke-dasharray). linkStyle, click, direction and accessibility lines are
// skipped; click is counted, so a caption can say its links aren't followed.

OM_EXPORT NSString * const OMMermaidFlowchartErrorDomain;
// NSNumber, 1-based line in the diagram source.
OM_EXPORT NSString * const OMMermaidFlowchartErrorLineNumberKey;

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
    NSMutableArray *_classNames;
    NSDictionary *_styleProperties;
}
@property (nonatomic, readonly) NSString *identifier;
// Display text; lines split on "<br>".
@property (nonatomic, readonly) NSString *label;
@property (nonatomic, readonly) OMMermaidFlowNodeShape shape;
// The CSS-like properties from classDef (the "default" class, then the
// node's classes in order) and style lines, later ones winning: "fill",
// "stroke", "color", "stroke-width", "stroke-dasharray" ... as written.
// nil when unstyled.
@property (nonatomic, readonly) NSDictionary *styleProperties;
@end

// A "subgraph id[Title] ... end" group.
@interface OMMermaidFlowSubgraph : NSObject
{
    NSString *_identifier;
    NSString *_title;
    NSString *_parentIdentifier;
    NSMutableArray *_nodeIdentifiers;
    NSMutableArray *_classNames;
    NSDictionary *_styleProperties;
}
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *title;
// The enclosing subgraph, or nil.
@property (nonatomic, readonly) NSString *parentIdentifier;
// The nodes it holds directly: each node belongs to the first subgraph it
// is mentioned in (as in Mermaid, even if mentioned outside before).
@property (nonatomic, readonly) NSArray *nodeIdentifiers;
// From class and style lines naming the subgraph; nil when unstyled.
@property (nonatomic, readonly) NSDictionary *styleProperties;
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
    NSArray *_subgraphs;
    NSUInteger _skippedStatementCount;
    NSUInteger _clickStatementCount;
}

// YES when the first meaningful line starts with "flowchart" or "graph".
+ (BOOL)sourceDeclaresFlowchart:(NSString *)source;
+ (instancetype)flowchartWithSource:(NSString *)source error:(NSError **)error;

@property (nonatomic, readonly) OMMermaidFlowDirection direction;
// In order of first mention.
@property (nonatomic, readonly) NSArray *nodes;
// An edge's end may name a subgraph instead of a node.
@property (nonatomic, readonly) NSArray *edges;
// In the order they open, so each comes after its parent.
@property (nonatomic, readonly) NSArray *subgraphs;
// linkStyle, click, direction ... lines that were skipped.
@property (nonatomic, readonly) NSUInteger skippedStatementCount;
// click lines among them: their links and callbacks do nothing here.
@property (nonatomic, readonly) NSUInteger clickStatementCount;

- (OMMermaidFlowNode *)nodeWithIdentifier:(NSString *)identifier;
- (OMMermaidFlowSubgraph *)subgraphWithIdentifier:(NSString *)identifier;

@end

// The diagram type a Mermaid source declares ("flowchart", "sequenceDiagram"...),
// from its first meaningful line, or nil.
OM_EXPORT NSString *OMMermaidDeclaredDiagramType(NSString *source);
