// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMermaidERLayout.h"
#import "OMMermaidERDiagram.h"

#include <math.h>

const NSUInteger OMMermaidERLayoutMaximumEntities = 40;
const NSUInteger OMMermaidERLayoutMaximumRelationships = 80;

// Ordering sweeps over the rank assignment. Four passes settle the small graphs
// this renderer accepts; more passes stop changing the result.
static const NSUInteger OMMermaidERLayoutOrderingSweeps = 4;

@interface OMMermaidERAttributeRowLayout ()
- (instancetype)initWithAttribute:(OMMermaidERAttribute *)attribute
                            frame:(NSRect)frame
                        typeFrame:(NSRect)typeFrame
                        nameFrame:(NSRect)nameFrame
                         keyFrame:(NSRect)keyFrame
                     commentFrame:(NSRect)commentFrame;
@end

@interface OMMermaidEREntityLayout ()
- (instancetype)initWithEntity:(OMMermaidEREntity *)entity
                         frame:(NSRect)frame
                    titleFrame:(NSRect)titleFrame
                 attributeRows:(NSArray *)attributeRows
                          rank:(NSUInteger)rank
                   orderInRank:(NSUInteger)orderInRank;
@end

@interface OMMermaidEREdgeLayout ()
- (instancetype)initWithRelationship:(OMMermaidERRelationship *)relationship
                              points:(NSArray *)points
                          labelFrame:(NSRect)labelFrame;
@end

@interface OMMermaidERDiagramLayout ()
- (BOOL)om_buildWithDiagram:(OMMermaidERDiagram *)diagram
                    metrics:(OMMermaidERLayoutMetrics *)metrics
                   measurer:(id<OMMermaidERTextMeasuring>)measurer;
@end

#pragma mark - Metrics

@implementation OMMermaidERLayoutMetrics

@synthesize titleHeight = _titleHeight;
@synthesize attributeRowHeight = _attributeRowHeight;
@synthesize boxHorizontalPadding = _boxHorizontalPadding;
@synthesize columnGap = _columnGap;
@synthesize minimumBoxWidth = _minimumBoxWidth;
@synthesize rankSpacing = _rankSpacing;
@synthesize siblingSpacing = _siblingSpacing;
@synthesize edgeLaneSpacing = _edgeLaneSpacing;
@synthesize labelHeight = _labelHeight;
@synthesize margin = _margin;

+ (instancetype)defaultMetrics
{
    return [[[self alloc] init] autorelease];
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _titleHeight = 26.0;
        _attributeRowHeight = 18.0;
        _boxHorizontalPadding = 8.0;
        _columnGap = 10.0;
        _minimumBoxWidth = 90.0;
        _rankSpacing = 56.0;
        _siblingSpacing = 36.0;
        _edgeLaneSpacing = 18.0;
        _labelHeight = 14.0;
        _margin = 12.0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    OMMermaidERLayoutMetrics *copy = [[[self class] allocWithZone:zone] init];
    if (copy != nil) {
        [copy setTitleHeight:_titleHeight];
        [copy setAttributeRowHeight:_attributeRowHeight];
        [copy setBoxHorizontalPadding:_boxHorizontalPadding];
        [copy setColumnGap:_columnGap];
        [copy setMinimumBoxWidth:_minimumBoxWidth];
        [copy setRankSpacing:_rankSpacing];
        [copy setSiblingSpacing:_siblingSpacing];
        [copy setEdgeLaneSpacing:_edgeLaneSpacing];
        [copy setLabelHeight:_labelHeight];
        [copy setMargin:_margin];
    }
    return copy;
}

@end

#pragma mark - Layout value objects

@implementation OMMermaidERAttributeRowLayout

@synthesize attribute = _attribute;
@synthesize frame = _frame;
@synthesize typeFrame = _typeFrame;
@synthesize nameFrame = _nameFrame;
@synthesize keyFrame = _keyFrame;
@synthesize commentFrame = _commentFrame;

- (instancetype)initWithAttribute:(OMMermaidERAttribute *)attribute
                            frame:(NSRect)frame
                        typeFrame:(NSRect)typeFrame
                        nameFrame:(NSRect)nameFrame
                         keyFrame:(NSRect)keyFrame
                     commentFrame:(NSRect)commentFrame
{
    self = [super init];
    if (self != nil) {
        _attribute = [attribute retain];
        _frame = frame;
        _typeFrame = typeFrame;
        _nameFrame = nameFrame;
        _keyFrame = keyFrame;
        _commentFrame = commentFrame;
    }
    return self;
}

- (void)dealloc
{
    [_attribute release];
    [super dealloc];
}

@end

@implementation OMMermaidEREntityLayout

@synthesize entity = _entity;
@synthesize frame = _frame;
@synthesize titleFrame = _titleFrame;
@synthesize attributeRows = _attributeRows;
@synthesize rank = _rank;
@synthesize orderInRank = _orderInRank;

- (instancetype)initWithEntity:(OMMermaidEREntity *)entity
                         frame:(NSRect)frame
                    titleFrame:(NSRect)titleFrame
                 attributeRows:(NSArray *)attributeRows
                          rank:(NSUInteger)rank
                   orderInRank:(NSUInteger)orderInRank
{
    self = [super init];
    if (self != nil) {
        _entity = [entity retain];
        _frame = frame;
        _titleFrame = titleFrame;
        _attributeRows = [attributeRows copy];
        _rank = rank;
        _orderInRank = orderInRank;
    }
    return self;
}

- (void)dealloc
{
    [_entity release];
    [_attributeRows release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ rank=%lu order=%lu frame=%@>",
            NSStringFromClass([self class]),
            [_entity name],
            (unsigned long)_rank,
            (unsigned long)_orderInRank,
            NSStringFromRect(_frame)];
}

@end

@implementation OMMermaidEREdgeLayout

@synthesize relationship = _relationship;
@synthesize points = _points;
@synthesize labelFrame = _labelFrame;

- (instancetype)initWithRelationship:(OMMermaidERRelationship *)relationship
                              points:(NSArray *)points
                          labelFrame:(NSRect)labelFrame
{
    self = [super init];
    if (self != nil) {
        _relationship = [relationship retain];
        _points = [points copy];
        _labelFrame = labelFrame;
    }
    return self;
}

- (void)dealloc
{
    [_relationship release];
    [_points release];
    [super dealloc];
}

- (NSPoint)startPoint
{
    if ([_points count] == 0) {
        return NSZeroPoint;
    }
    return [[_points objectAtIndex:0] pointValue];
}

- (NSPoint)endPoint
{
    if ([_points count] == 0) {
        return NSZeroPoint;
    }
    return [[_points lastObject] pointValue];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ -> %@ points=%lu>",
            NSStringFromClass([self class]),
            [_relationship leftEntityName],
            [_relationship rightEntityName],
            (unsigned long)[_points count]];
}

@end

#pragma mark - Measuring helpers

static CGFloat OMMermaidMeasureAttributeText(id<OMMermaidERTextMeasuring> measurer, NSString *text)
{
    if (text == nil || [text length] == 0) {
        return 0.0;
    }
    return [measurer mermaidWidthForAttributeText:text];
}

static NSString *OMMermaidJoinedKeys(OMMermaidERAttribute *attribute)
{
    NSArray *keys = [attribute keys];
    if ([keys count] == 0) {
        return nil;
    }
    return [keys componentsJoinedByString:@","];
}

#pragma mark - Ordering helpers

// Stable insertion sort of one rank by barycenter. Stability is what makes the
// sweeps converge to the same order on every run.
static void OMMermaidStableSortRank(NSUInteger *nodes,
                                    CGFloat *barycenters,
                                    NSUInteger count)
{
    NSUInteger i = 1;
    for (; i < count; i++) {
        NSUInteger node = nodes[i];
        CGFloat key = barycenters[i];
        NSUInteger j = i;
        while (j > 0 && barycenters[j - 1] > key) {
            nodes[j] = nodes[j - 1];
            barycenters[j] = barycenters[j - 1];
            j -= 1;
        }
        nodes[j] = node;
        barycenters[j] = key;
    }
}

#pragma mark - Diagram layout

@implementation OMMermaidERDiagramLayout

@synthesize size = _size;
@synthesize entityLayouts = _entityLayouts;
@synthesize edgeLayouts = _edgeLayouts;

+ (instancetype)layoutForDiagram:(OMMermaidERDiagram *)diagram
                         metrics:(OMMermaidERLayoutMetrics *)metrics
                        measurer:(id<OMMermaidERTextMeasuring>)measurer
{
    if (diagram == nil || measurer == nil) {
        return nil;
    }
    if ([[diagram entities] count] == 0 ||
        [[diagram entities] count] > OMMermaidERLayoutMaximumEntities ||
        [[diagram relationships] count] > OMMermaidERLayoutMaximumRelationships) {
        return nil;
    }

    OMMermaidERLayoutMetrics *effectiveMetrics = metrics;
    if (effectiveMetrics == nil) {
        effectiveMetrics = [OMMermaidERLayoutMetrics defaultMetrics];
    }

    OMMermaidERDiagramLayout *layout = [[[self alloc] init] autorelease];
    if (![layout om_buildWithDiagram:diagram metrics:effectiveMetrics measurer:measurer]) {
        return nil;
    }
    return layout;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _entityLayoutsByName = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_entityLayouts release];
    [_edgeLayouts release];
    [_entityLayoutsByName release];
    [super dealloc];
}

- (OMMermaidEREntityLayout *)layoutForEntityNamed:(NSString *)name
{
    if (name == nil) {
        return nil;
    }
    return [_entityLayoutsByName objectForKey:name];
}

- (BOOL)om_buildWithDiagram:(OMMermaidERDiagram *)diagram
                    metrics:(OMMermaidERLayoutMetrics *)metrics
                   measurer:(id<OMMermaidERTextMeasuring>)measurer
{
    NSArray *entities = [diagram entities];
    NSArray *relationships = [diagram relationships];
    NSUInteger entityCount = [entities count];
    NSUInteger edgeCount = [relationships count];

    // Scalar working arrays live in autoreleased NSMutableData so that every
    // early return stays leak free.
#define OM_SCALAR_ARRAY(type, name, length) \
    type *name = (type *)[[NSMutableData dataWithLength:((length) > 0 ? (length) : 1) * sizeof(type)] mutableBytes]

    OM_SCALAR_ARRAY(CGFloat, boxWidth, entityCount);
    OM_SCALAR_ARRAY(CGFloat, boxHeight, entityCount);
    OM_SCALAR_ARRAY(CGFloat, typeColumnWidth, entityCount);
    OM_SCALAR_ARRAY(CGFloat, nameColumnWidth, entityCount);
    OM_SCALAR_ARRAY(CGFloat, keyColumnWidth, entityCount);
    OM_SCALAR_ARRAY(CGFloat, commentColumnWidth, entityCount);
    OM_SCALAR_ARRAY(CGFloat, boxX, entityCount);
    OM_SCALAR_ARRAY(CGFloat, boxY, entityCount);
    OM_SCALAR_ARRAY(NSUInteger, nodeRank, entityCount);
    OM_SCALAR_ARRAY(NSUInteger, nodeOrder, entityCount);

    // 1) Box sizing.
    NSMutableDictionary *indexesByName = [NSMutableDictionary dictionary];
    NSUInteger i = 0;
    for (; i < entityCount; i++) {
        OMMermaidEREntity *entity = [entities objectAtIndex:i];
        [indexesByName setObject:[NSNumber numberWithUnsignedInteger:i] forKey:[entity name]];

        CGFloat typeWidth = 0.0;
        CGFloat nameWidth = 0.0;
        CGFloat keyWidth = 0.0;
        CGFloat commentWidth = 0.0;
        for (OMMermaidERAttribute *attribute in [entity attributes]) {
            typeWidth = MAX(typeWidth, OMMermaidMeasureAttributeText(measurer, [attribute type]));
            nameWidth = MAX(nameWidth, OMMermaidMeasureAttributeText(measurer, [attribute name]));
            keyWidth = MAX(keyWidth, OMMermaidMeasureAttributeText(measurer, OMMermaidJoinedKeys(attribute)));
            commentWidth = MAX(commentWidth, OMMermaidMeasureAttributeText(measurer, [attribute comment]));
        }
        typeColumnWidth[i] = typeWidth;
        nameColumnWidth[i] = nameWidth;
        keyColumnWidth[i] = keyWidth;
        commentColumnWidth[i] = commentWidth;

        CGFloat padding = [metrics boxHorizontalPadding];
        CGFloat gap = [metrics columnGap];
        CGFloat bodyWidth = 0.0;
        NSUInteger attributeCount = [[entity attributes] count];
        if (attributeCount > 0) {
            bodyWidth = (padding * 2.0) + typeWidth + gap + nameWidth;
            if (keyWidth > 0.0) {
                bodyWidth += gap + keyWidth;
            }
            if (commentWidth > 0.0) {
                bodyWidth += gap + commentWidth;
            }
        }

        CGFloat titleWidth = [measurer mermaidWidthForEntityTitle:[entity displayName]] + (padding * 2.0);
        CGFloat width = MAX(MAX(titleWidth, bodyWidth), [metrics minimumBoxWidth]);
        boxWidth[i] = ceil(width);
        boxHeight[i] = [metrics titleHeight] + ((CGFloat)attributeCount * [metrics attributeRowHeight]);
    }

    // 2) Adjacency, then breadth-first ranking from the busiest entity of each
    //    connected component. Components share the rank rows, so they end up
    //    side by side rather than stacked.
    NSMutableArray *adjacency = [NSMutableArray arrayWithCapacity:entityCount];
    for (i = 0; i < entityCount; i++) {
        [adjacency addObject:[NSMutableArray array]];
    }

    OM_SCALAR_ARRAY(NSUInteger, edgeLeftIndex, edgeCount);
    OM_SCALAR_ARRAY(NSUInteger, edgeRightIndex, edgeCount);
    OM_SCALAR_ARRAY(NSUInteger, degree, entityCount);

    NSUInteger j = 0;
    for (; j < edgeCount; j++) {
        OMMermaidERRelationship *relationship = [relationships objectAtIndex:j];
        NSNumber *left = [indexesByName objectForKey:[relationship leftEntityName]];
        NSNumber *right = [indexesByName objectForKey:[relationship rightEntityName]];
        if (left == nil || right == nil) {
            return NO;
        }
        NSUInteger li = [left unsignedIntegerValue];
        NSUInteger ri = [right unsignedIntegerValue];
        edgeLeftIndex[j] = li;
        edgeRightIndex[j] = ri;
        degree[li] += 1;
        degree[ri] += 1;
        if (li != ri) {
            [[adjacency objectAtIndex:li] addObject:[NSNumber numberWithUnsignedInteger:ri]];
            [[adjacency objectAtIndex:ri] addObject:[NSNumber numberWithUnsignedInteger:li]];
        }
    }

    OM_SCALAR_ARRAY(BOOL, visited, entityCount);
    NSMutableArray *ranks = [NSMutableArray array];
    NSUInteger visitedCount = 0;
    while (visitedCount < entityCount) {
        NSUInteger root = NSNotFound;
        for (i = 0; i < entityCount; i++) {
            if (visited[i]) {
                continue;
            }
            if (root == NSNotFound || degree[i] > degree[root]) {
                root = i;
            }
        }
        if (root == NSNotFound) {
            break;
        }

        NSMutableArray *queue = [NSMutableArray arrayWithObject:[NSNumber numberWithUnsignedInteger:root]];
        visited[root] = YES;
        nodeRank[root] = 0;
        visitedCount += 1;
        NSUInteger head = 0;
        while (head < [queue count]) {
            NSUInteger current = [[queue objectAtIndex:head] unsignedIntegerValue];
            head += 1;
            while ([ranks count] <= nodeRank[current]) {
                [ranks addObject:[NSMutableArray array]];
            }
            [[ranks objectAtIndex:nodeRank[current]]
                addObject:[NSNumber numberWithUnsignedInteger:current]];

            for (NSNumber *neighbor in [adjacency objectAtIndex:current]) {
                NSUInteger next = [neighbor unsignedIntegerValue];
                if (visited[next]) {
                    continue;
                }
                visited[next] = YES;
                nodeRank[next] = nodeRank[current] + 1;
                visitedCount += 1;
                [queue addObject:neighbor];
            }
        }
    }

    NSUInteger rankCount = [ranks count];
    if (rankCount == 0) {
        return NO;
    }

    // 3) Barycenter sweeps to reduce crossings, alternating downward and upward.
    for (i = 0; i < rankCount; i++) {
        NSMutableArray *rank = [ranks objectAtIndex:i];
        NSUInteger position = 0;
        for (; position < [rank count]; position++) {
            nodeOrder[[[rank objectAtIndex:position] unsignedIntegerValue]] = position;
        }
    }

    NSUInteger sweep = 0;
    for (; sweep < OMMermaidERLayoutOrderingSweeps; sweep++) {
        BOOL downward = ((sweep % 2) == 0);
        NSUInteger step = 0;
        for (; step + 1 < rankCount; step++) {
            NSUInteger rankIndex = downward ? (step + 1) : (rankCount - 2 - step);
            NSUInteger referenceRank = downward ? (rankIndex - 1) : (rankIndex + 1);
            NSMutableArray *rank = [ranks objectAtIndex:rankIndex];
            NSUInteger count = [rank count];
            if (count < 2) {
                continue;
            }

            OM_SCALAR_ARRAY(NSUInteger, nodes, count);
            OM_SCALAR_ARRAY(CGFloat, barycenters, count);
            NSUInteger position = 0;
            for (; position < count; position++) {
                NSUInteger node = [[rank objectAtIndex:position] unsignedIntegerValue];
                nodes[position] = node;

                CGFloat total = 0.0;
                NSUInteger neighborCount = 0;
                for (NSNumber *neighbor in [adjacency objectAtIndex:node]) {
                    NSUInteger other = [neighbor unsignedIntegerValue];
                    if (nodeRank[other] != referenceRank) {
                        continue;
                    }
                    total += (CGFloat)nodeOrder[other];
                    neighborCount += 1;
                }
                barycenters[position] = neighborCount > 0
                    ? (total / (CGFloat)neighborCount)
                    : (CGFloat)position;
            }

            OMMermaidStableSortRank(nodes, barycenters, count);

            [rank removeAllObjects];
            for (position = 0; position < count; position++) {
                [rank addObject:[NSNumber numberWithUnsignedInteger:nodes[position]]];
                nodeOrder[nodes[position]] = position;
            }
        }
    }

    // 4) Horizontal placement: pack each rank left to right, then center the
    //    ranks against the widest one.
    CGFloat widestRank = 0.0;
    OM_SCALAR_ARRAY(CGFloat, rankWidth, rankCount);
    for (i = 0; i < rankCount; i++) {
        NSMutableArray *rank = [ranks objectAtIndex:i];
        CGFloat cursor = 0.0;
        for (NSNumber *nodeNumber in rank) {
            NSUInteger node = [nodeNumber unsignedIntegerValue];
            boxX[node] = cursor;
            cursor += boxWidth[node] + [metrics siblingSpacing];
        }
        rankWidth[i] = [rank count] > 0 ? (cursor - [metrics siblingSpacing]) : 0.0;
        widestRank = MAX(widestRank, rankWidth[i]);
    }
    for (i = 0; i < rankCount; i++) {
        CGFloat offset = [metrics margin] + ((widestRank - rankWidth[i]) / 2.0);
        for (NSNumber *nodeNumber in [ranks objectAtIndex:i]) {
            boxX[[nodeNumber unsignedIntegerValue]] += offset;
        }
    }

    // 5) Assign every edge to the gap it runs through, and to a lane within it.
    //    Gap g is the space above rank g; gap rankCount is the space below the
    //    last rank, which is where same-rank edges dip.
    NSUInteger gapCount = rankCount + 1;
    OM_SCALAR_ARRAY(NSUInteger, edgeGap, edgeCount);
    OM_SCALAR_ARRAY(NSUInteger, edgeLane, edgeCount);
    OM_SCALAR_ARRAY(NSUInteger, gapLaneCount, gapCount);

    for (j = 0; j < edgeCount; j++) {
        NSUInteger leftRank = nodeRank[edgeLeftIndex[j]];
        NSUInteger rightRank = nodeRank[edgeRightIndex[j]];
        NSUInteger gap = (leftRank == rightRank) ? (leftRank + 1) : MAX(leftRank, rightRank);
        edgeGap[j] = gap;
        edgeLane[j] = gapLaneCount[gap];
        gapLaneCount[gap] += 1;
    }

    // 6) Vertical placement: gaps grow to fit the lanes routed through them.
    CGFloat laneSpacing = MAX([metrics edgeLaneSpacing], [metrics labelHeight] + 4.0);
    OM_SCALAR_ARRAY(CGFloat, gapHeight, gapCount);
    OM_SCALAR_ARRAY(CGFloat, rankHeight, rankCount);
    OM_SCALAR_ARRAY(CGFloat, rankTop, rankCount);

    for (i = 0; i < gapCount; i++) {
        CGFloat floorHeight = (i == 0 || i == rankCount) ? [metrics margin] : [metrics rankSpacing];
        CGFloat laneHeight = gapLaneCount[i] > 0
            ? ((CGFloat)(gapLaneCount[i] + 1) * laneSpacing)
            : 0.0;
        gapHeight[i] = MAX(floorHeight, laneHeight);
    }
    for (i = 0; i < rankCount; i++) {
        CGFloat tallest = 0.0;
        for (NSNumber *nodeNumber in [ranks objectAtIndex:i]) {
            tallest = MAX(tallest, boxHeight[[nodeNumber unsignedIntegerValue]]);
        }
        rankHeight[i] = tallest;
        rankTop[i] = (i == 0)
            ? gapHeight[0]
            : (rankTop[i - 1] + rankHeight[i - 1] + gapHeight[i]);
        for (NSNumber *nodeNumber in [ranks objectAtIndex:i]) {
            boxY[[nodeNumber unsignedIntegerValue]] = rankTop[i];
        }
    }

    CGFloat contentHeight = rankTop[rankCount - 1] + rankHeight[rankCount - 1] + gapHeight[rankCount];

    // 7) Attachment points. Every edge end that meets a box gets its own slot on
    //    that box edge, ordered by where the far end sits, so parallel edges stay
    //    visually separated.
    NSMutableArray *bottomSlots = [NSMutableArray arrayWithCapacity:entityCount];
    NSMutableArray *topSlots = [NSMutableArray arrayWithCapacity:entityCount];
    for (i = 0; i < entityCount; i++) {
        [bottomSlots addObject:[NSMutableArray array]];
        [topSlots addObject:[NSMutableArray array]];
    }

    for (j = 0; j < edgeCount; j++) {
        NSUInteger ends[2];
        ends[0] = edgeLeftIndex[j];
        ends[1] = edgeRightIndex[j];
        NSUInteger which = 0;
        for (; which < 2; which++) {
            NSUInteger node = ends[which];
            NSUInteger other = ends[1 - which];
            CGFloat otherCenter = boxX[other] + (boxWidth[other] / 2.0);
            BOOL attachesToBottom = (nodeRank[node] < edgeGap[j]);
            NSDictionary *slot = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithUnsignedInteger:j], @"edge",
                [NSNumber numberWithUnsignedInteger:which], @"end",
                [NSNumber numberWithDouble:otherCenter], @"otherCenter",
                nil];
            NSMutableArray *list = attachesToBottom
                ? [bottomSlots objectAtIndex:node]
                : [topSlots objectAtIndex:node];
            [list addObject:slot];
        }
    }

    NSComparator slotComparator = ^NSComparisonResult(id first, id second) {
        double firstCenter = [[first objectForKey:@"otherCenter"] doubleValue];
        double secondCenter = [[second objectForKey:@"otherCenter"] doubleValue];
        if (firstCenter < secondCenter) {
            return NSOrderedAscending;
        }
        if (firstCenter > secondCenter) {
            return NSOrderedDescending;
        }
        NSUInteger firstEdge = [[first objectForKey:@"edge"] unsignedIntegerValue];
        NSUInteger secondEdge = [[second objectForKey:@"edge"] unsignedIntegerValue];
        if (firstEdge != secondEdge) {
            return firstEdge < secondEdge ? NSOrderedAscending : NSOrderedDescending;
        }
        NSUInteger firstEnd = [[first objectForKey:@"end"] unsignedIntegerValue];
        NSUInteger secondEnd = [[second objectForKey:@"end"] unsignedIntegerValue];
        if (firstEnd == secondEnd) {
            return NSOrderedSame;
        }
        return firstEnd < secondEnd ? NSOrderedAscending : NSOrderedDescending;
    };

    // Attachment point per (edge, end), indexed as (edge * 2 + end).
    OM_SCALAR_ARRAY(NSPoint, attachment, edgeCount * 2);
    for (i = 0; i < entityCount; i++) {
        NSUInteger side = 0;
        for (; side < 2; side++) {
            NSMutableArray *list = (side == 0)
                ? [bottomSlots objectAtIndex:i]
                : [topSlots objectAtIndex:i];
            NSArray *sorted = [list sortedArrayUsingComparator:slotComparator];
            NSUInteger count = [sorted count];
            CGFloat edgeY = (side == 0) ? (boxY[i] + boxHeight[i]) : boxY[i];
            NSUInteger position = 0;
            for (; position < count; position++) {
                NSDictionary *slot = [sorted objectAtIndex:position];
                NSUInteger edgeIndex = [[slot objectForKey:@"edge"] unsignedIntegerValue];
                NSUInteger end = [[slot objectForKey:@"end"] unsignedIntegerValue];
                CGFloat fraction = (CGFloat)(position + 1) / (CGFloat)(count + 1);
                attachment[edgeIndex * 2 + end] =
                    NSMakePoint(boxX[i] + (boxWidth[i] * fraction), edgeY);
            }
        }
    }

    // 8) Route each edge and place its label on the horizontal run.
    NSMutableArray *edgeLayouts = [NSMutableArray arrayWithCapacity:edgeCount];
    CGFloat contentRight = [metrics margin] + widestRank;
    CGFloat contentLeft = [metrics margin];
    for (j = 0; j < edgeCount; j++) {
        OMMermaidERRelationship *relationship = [relationships objectAtIndex:j];
        NSPoint start = attachment[j * 2];
        NSPoint end = attachment[j * 2 + 1];
        NSUInteger gap = edgeGap[j];
        CGFloat gapTop = (gap == 0) ? 0.0 : (rankTop[gap - 1] + rankHeight[gap - 1]);
        CGFloat laneY = gapTop + ((CGFloat)(edgeLane[j] + 1) * laneSpacing);

        BOOL sameRank = (nodeRank[edgeLeftIndex[j]] == nodeRank[edgeRightIndex[j]]);
        BOOL straight = (!sameRank && fabs(start.x - end.x) < 0.5);

        NSMutableArray *points = [NSMutableArray array];
        [points addObject:[NSValue valueWithPoint:start]];
        if (!straight) {
            [points addObject:[NSValue valueWithPoint:NSMakePoint(start.x, laneY)]];
            [points addObject:[NSValue valueWithPoint:NSMakePoint(end.x, laneY)]];
        }
        [points addObject:[NSValue valueWithPoint:end]];

        NSRect labelFrame = NSZeroRect;
        NSString *label = [relationship label];
        if (label != nil && [label length] > 0) {
            CGFloat labelWidth = [measurer mermaidWidthForRelationshipLabel:label] + 8.0;
            CGFloat labelX = ((start.x + end.x) / 2.0) - (labelWidth / 2.0);
            if (straight) {
                // Nothing runs horizontally here, so sit the label beside the line.
                labelX = start.x + 4.0;
            }
            labelFrame = NSMakeRect(labelX,
                                    laneY - ([metrics labelHeight] / 2.0),
                                    labelWidth,
                                    [metrics labelHeight]);
            contentLeft = MIN(contentLeft, NSMinX(labelFrame));
            contentRight = MAX(contentRight, NSMaxX(labelFrame));
        }

        [edgeLayouts addObject:[[[OMMermaidEREdgeLayout alloc]
            initWithRelationship:relationship
                          points:points
                      labelFrame:labelFrame] autorelease]];
    }

    // A label may overhang the left edge; shift everything back into positive
    // coordinates rather than letting the drawing origin go negative.
    CGFloat leftShift = (contentLeft < [metrics margin]) ? ([metrics margin] - contentLeft) : 0.0;
    if (leftShift > 0.0) {
        for (i = 0; i < entityCount; i++) {
            boxX[i] += leftShift;
        }
        NSMutableArray *shifted = [NSMutableArray arrayWithCapacity:edgeCount];
        for (OMMermaidEREdgeLayout *edge in edgeLayouts) {
            NSMutableArray *points = [NSMutableArray array];
            for (NSValue *value in [edge points]) {
                NSPoint point = [value pointValue];
                point.x += leftShift;
                [points addObject:[NSValue valueWithPoint:point]];
            }
            NSRect labelFrame = [edge labelFrame];
            if (!NSIsEmptyRect(labelFrame)) {
                labelFrame.origin.x += leftShift;
            }
            [shifted addObject:[[[OMMermaidEREdgeLayout alloc]
                initWithRelationship:[edge relationship]
                              points:points
                          labelFrame:labelFrame] autorelease]];
        }
        edgeLayouts = shifted;
        contentRight += leftShift;
    }

    // 9) Entity frames, including the column rects each attribute row draws into.
    NSMutableArray *entityLayouts = [NSMutableArray arrayWithCapacity:entityCount];
    for (i = 0; i < entityCount; i++) {
        OMMermaidEREntity *entity = [entities objectAtIndex:i];
        NSRect frame = NSMakeRect(boxX[i], boxY[i], boxWidth[i], boxHeight[i]);
        NSRect titleFrame = NSMakeRect(boxX[i], boxY[i], boxWidth[i], [metrics titleHeight]);

        NSMutableArray *rows = [NSMutableArray array];
        NSUInteger rowIndex = 0;
        for (OMMermaidERAttribute *attribute in [entity attributes]) {
            CGFloat rowY = boxY[i] + [metrics titleHeight] + ((CGFloat)rowIndex * [metrics attributeRowHeight]);
            NSRect rowFrame = NSMakeRect(boxX[i], rowY, boxWidth[i], [metrics attributeRowHeight]);

            CGFloat cursor = boxX[i] + [metrics boxHorizontalPadding];
            NSRect typeFrame = NSMakeRect(cursor, rowY, typeColumnWidth[i], [metrics attributeRowHeight]);
            cursor += typeColumnWidth[i] + [metrics columnGap];
            NSRect nameFrame = NSMakeRect(cursor, rowY, nameColumnWidth[i], [metrics attributeRowHeight]);
            cursor += nameColumnWidth[i];

            NSRect keyFrame = NSMakeRect(cursor, rowY, 0.0, [metrics attributeRowHeight]);
            if (keyColumnWidth[i] > 0.0) {
                cursor += [metrics columnGap];
                keyFrame.origin.x = cursor;
                if ([[attribute keys] count] > 0) {
                    keyFrame.size.width = keyColumnWidth[i];
                }
                cursor += keyColumnWidth[i];
            }

            NSRect commentFrame = NSMakeRect(cursor, rowY, 0.0, [metrics attributeRowHeight]);
            if (commentColumnWidth[i] > 0.0) {
                cursor += [metrics columnGap];
                commentFrame.origin.x = cursor;
                if ([attribute comment] != nil && [[attribute comment] length] > 0) {
                    commentFrame.size.width = commentColumnWidth[i];
                }
            }

            [rows addObject:[[[OMMermaidERAttributeRowLayout alloc]
                initWithAttribute:attribute
                            frame:rowFrame
                        typeFrame:typeFrame
                        nameFrame:nameFrame
                         keyFrame:keyFrame
                     commentFrame:commentFrame] autorelease]];
            rowIndex += 1;
        }

        OMMermaidEREntityLayout *entityLayout = [[[OMMermaidEREntityLayout alloc]
            initWithEntity:entity
                     frame:frame
                titleFrame:titleFrame
             attributeRows:rows
                      rank:nodeRank[i]
               orderInRank:nodeOrder[i]] autorelease];
        [entityLayouts addObject:entityLayout];
        [_entityLayoutsByName setObject:entityLayout forKey:[entity name]];
    }

#undef OM_SCALAR_ARRAY

    _entityLayouts = [entityLayouts copy];
    _edgeLayouts = [edgeLayouts copy];
    _size = NSMakeSize(ceil(contentRight + [metrics margin]), ceil(contentHeight));
    return YES;
}

@end
