// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import "OMExport.h"

@class OMMermaidERAttribute;
@class OMMermaidEREntity;
@class OMMermaidERRelationship;
@class OMMermaidERDiagram;

// Geometry is produced in diagram coordinates: origin at the top left, x growing
// right, y growing down. Drawing code flips as needed for its own context.

// Layout refuses diagrams past these sizes, so callers fall back to rendering the
// diagram source as a code block instead of drawing something unreadable.
OM_EXPORT const NSUInteger OMMermaidERLayoutMaximumEntities;
OM_EXPORT const NSUInteger OMMermaidERLayoutMaximumRelationships;

// Text widths come from the caller so that layout stays independent of AppKit
// font metrics, which keeps geometry tests deterministic across machines.
@protocol OMMermaidERTextMeasuring <NSObject>
- (CGFloat)mermaidWidthForEntityTitle:(NSString *)title;
- (CGFloat)mermaidWidthForAttributeText:(NSString *)text;
- (CGFloat)mermaidWidthForRelationshipLabel:(NSString *)label;
@end

@interface OMMermaidERLayoutMetrics : NSObject <NSCopying>
{
    CGFloat _titleHeight;
    CGFloat _attributeRowHeight;
    CGFloat _boxHorizontalPadding;
    CGFloat _columnGap;
    CGFloat _minimumBoxWidth;
    CGFloat _rankSpacing;
    CGFloat _siblingSpacing;
    CGFloat _edgeLaneSpacing;
    CGFloat _labelHeight;
    CGFloat _margin;
}

@property (nonatomic, assign) CGFloat titleHeight;
@property (nonatomic, assign) CGFloat attributeRowHeight;
// Padding inside an entity box, applied on each side.
@property (nonatomic, assign) CGFloat boxHorizontalPadding;
// Gap between the type, name, key, and comment columns.
@property (nonatomic, assign) CGFloat columnGap;
@property (nonatomic, assign) CGFloat minimumBoxWidth;
// Minimum vertical space between two ranks of boxes.
@property (nonatomic, assign) CGFloat rankSpacing;
// Horizontal space between two boxes in the same rank.
@property (nonatomic, assign) CGFloat siblingSpacing;
// Vertical distance between parallel horizontal edge runs in one gap.
@property (nonatomic, assign) CGFloat edgeLaneSpacing;
@property (nonatomic, assign) CGFloat labelHeight;
// Space reserved around the whole drawing.
@property (nonatomic, assign) CGFloat margin;

+ (instancetype)defaultMetrics;

@end

@interface OMMermaidERAttributeRowLayout : NSObject
{
    OMMermaidERAttribute *_attribute;
    NSRect _frame;
    NSRect _typeFrame;
    NSRect _nameFrame;
    NSRect _keyFrame;
    NSRect _commentFrame;
}

@property (nonatomic, readonly) OMMermaidERAttribute *attribute;
// Full row, spanning the entity box width.
@property (nonatomic, readonly) NSRect frame;
@property (nonatomic, readonly) NSRect typeFrame;
@property (nonatomic, readonly) NSRect nameFrame;
// Zero width when the attribute carries no key markers.
@property (nonatomic, readonly) NSRect keyFrame;
// Zero width when the attribute carries no comment.
@property (nonatomic, readonly) NSRect commentFrame;

@end

@interface OMMermaidEREntityLayout : NSObject
{
    OMMermaidEREntity *_entity;
    NSRect _frame;
    NSRect _titleFrame;
    NSArray *_attributeRows;
    NSUInteger _rank;
    NSUInteger _orderInRank;
}

@property (nonatomic, readonly) OMMermaidEREntity *entity;
@property (nonatomic, readonly) NSRect frame;
@property (nonatomic, readonly) NSRect titleFrame;
// OMMermaidERAttributeRowLayout, in attribute order.
@property (nonatomic, readonly) NSArray *attributeRows;
@property (nonatomic, readonly) NSUInteger rank;
@property (nonatomic, readonly) NSUInteger orderInRank;

@end

@interface OMMermaidEREdgeLayout : NSObject
{
    OMMermaidERRelationship *_relationship;
    NSArray *_points;
    NSRect _labelFrame;
}

@property (nonatomic, readonly) OMMermaidERRelationship *relationship;
// NSValue-wrapped NSPoint, at least two entries, forming an orthogonal polyline.
// The first point sits on the left entity and carries its cardinality marker;
// the last point sits on the right entity and carries the other marker.
@property (nonatomic, readonly) NSArray *points;
// Zero-sized when the relationship has no label.
@property (nonatomic, readonly) NSRect labelFrame;

- (NSPoint)startPoint;
- (NSPoint)endPoint;

@end

@interface OMMermaidERDiagramLayout : NSObject
{
    NSSize _size;
    NSArray *_entityLayouts;
    NSArray *_edgeLayouts;
    NSMutableDictionary *_entityLayoutsByName;
}

// Returns nil when the diagram is empty or exceeds the size limits above.
+ (instancetype)layoutForDiagram:(OMMermaidERDiagram *)diagram
                         metrics:(OMMermaidERLayoutMetrics *)metrics
                        measurer:(id<OMMermaidERTextMeasuring>)measurer;

@property (nonatomic, readonly) NSSize size;
// OMMermaidEREntityLayout, in diagram entity order.
@property (nonatomic, readonly) NSArray *entityLayouts;
// OMMermaidEREdgeLayout, in diagram relationship order.
@property (nonatomic, readonly) NSArray *edgeLayouts;

- (OMMermaidEREntityLayout *)layoutForEntityNamed:(NSString *)name;

@end
