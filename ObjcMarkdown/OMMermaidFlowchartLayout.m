// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMermaidFlowchartLayout.h"
#import "OMMermaidFlowchart.h"
#include <math.h>

static const CGFloat OMFlowNodePaddingX = 14.0;
static const CGFloat OMFlowNodePaddingY = 9.0;
static const CGFloat OMFlowMinimumNodeWidth = 56.0;
static const CGFloat OMFlowRankGap = 44.0;
static const CGFloat OMFlowSiblingGap = 28.0;
static const CGFloat OMFlowLabelPadding = 4.0;
static const CGFloat OMFlowMargin = 10.0;
static const CGFloat OMFlowSelfLoopReach = 18.0;

NSString *OMMermaidFlowDisplayText(NSString *label)
{
    NSString *text = label != nil ? label : @"";
    NSArray *breaks = [NSArray arrayWithObjects:@"<br />", @"<br/>", @"<br>", @"<BR>", nil];
    for (NSString *mark in breaks) {
        text = [text stringByReplacingOccurrencesOfString:mark withString:@"\n"];
    }
    return text;
}

@implementation OMMermaidFlowNodeLayout

@synthesize node = _node;
@synthesize text = _text;
@synthesize frame = _frame;

- (instancetype)initWithNode:(OMMermaidFlowNode *)node text:(NSString *)text frame:(NSRect)frame
{
    self = [super init];
    if (self != nil) {
        _node = [node retain];
        _text = [text copy];
        _frame = frame;
    }
    return self;
}

- (void)dealloc
{
    [_node release];
    [_text release];
    [super dealloc];
}

@end

@implementation OMMermaidFlowEdgeLayout

@synthesize edge = _edge;
@synthesize points = _points;
@synthesize labelFrame = _labelFrame;

- (instancetype)initWithEdge:(OMMermaidFlowEdge *)edge points:(NSArray *)points labelFrame:(NSRect)labelFrame
{
    self = [super init];
    if (self != nil) {
        _edge = [edge retain];
        _points = [points copy];
        _labelFrame = labelFrame;
    }
    return self;
}

- (void)dealloc
{
    [_edge release];
    [_points release];
    [super dealloc];
}

@end

// Where the ray from the centre of frame towards target leaves the shape.
static NSPoint OMFlowBoundaryPoint(NSRect frame, OMMermaidFlowNodeShape shape, NSPoint target)
{
    NSPoint center = NSMakePoint(NSMidX(frame), NSMidY(frame));
    CGFloat dx = target.x - center.x;
    CGFloat dy = target.y - center.y;
    if (fabs(dx) < 0.001 && fabs(dy) < 0.001) {
        return center;
    }
    CGFloat halfWidth = NSWidth(frame) / 2.0;
    CGFloat halfHeight = NSHeight(frame) / 2.0;
    CGFloat t = 1.0;
    if (shape == OMMermaidFlowNodeShapeDiamond) {
        t = 1.0 / (fabs(dx) / halfWidth + fabs(dy) / halfHeight);
    } else if (shape == OMMermaidFlowNodeShapeCircle) {
        t = MIN(halfWidth, halfHeight) / sqrt(dx * dx + dy * dy);
    } else {
        CGFloat tx = fabs(dx) > 0.001 ? halfWidth / fabs(dx) : INFINITY;
        CGFloat ty = fabs(dy) > 0.001 ? halfHeight / fabs(dy) : INFINITY;
        t = MIN(tx, ty);
    }
    return NSMakePoint(center.x + dx * t, center.y + dy * t);
}

@implementation OMMermaidFlowchartLayout

@synthesize nodeLayouts = _nodeLayouts;
@synthesize edgeLayouts = _edgeLayouts;
@synthesize size = _size;

- (void)dealloc
{
    [_nodeLayouts release];
    [_edgeLayouts release];
    [super dealloc];
}

- (OMMermaidFlowNodeLayout *)layoutForNodeIdentifier:(NSString *)identifier
{
    for (OMMermaidFlowNodeLayout *layout in _nodeLayouts) {
        if ([[[layout node] identifier] isEqualToString:identifier]) {
            return layout;
        }
    }
    return nil;
}

+ (instancetype)layoutForFlowchart:(OMMermaidFlowchart *)flowchart
                          measurer:(id<OMMermaidFlowTextMeasuring>)measurer
{
    NSArray *nodes = [flowchart nodes];
    NSUInteger count = [nodes count];
    if (count == 0 || measurer == nil) {
        return nil;
    }
    NSMutableDictionary *indexOf = [NSMutableDictionary dictionaryWithCapacity:count];
    NSUInteger i = 0;
    for (; i < count; i++) {
        [indexOf setObject:[NSNumber numberWithUnsignedInteger:i] forKey:[[nodes objectAtIndex:i] identifier]];
    }

    // Links between distinct nodes, as index pairs.
    NSMutableArray *links = [NSMutableArray array];
    for (OMMermaidFlowEdge *edge in [flowchart edges]) {
        NSNumber *from = [indexOf objectForKey:[edge fromIdentifier]];
        NSNumber *to = [indexOf objectForKey:[edge toIdentifier]];
        if (from != nil && to != nil && ![from isEqual:to]) {
            [links addObject:[NSArray arrayWithObjects:from, to, nil]];
        }
    }

    // Break cycles: a link back to a node on the DFS stack is reversed.
    NSMutableArray *successors = [NSMutableArray arrayWithCapacity:count];
    for (i = 0; i < count; i++) {
        [successors addObject:[NSMutableArray array]];
    }
    for (NSArray *link in links) {
        [[successors objectAtIndex:[[link objectAtIndex:0] unsignedIntegerValue]] addObject:[link objectAtIndex:1]];
    }
    NSMutableIndexSet *reversed = [NSMutableIndexSet indexSet];
    {
        int *state = (int *)calloc(count, sizeof(int)); // 0 new, 1 on stack, 2 done
        for (i = 0; i < count; i++) {
            if (state[i] != 0) {
                continue;
            }
            NSMutableArray *stack = [NSMutableArray arrayWithObject:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:i], [NSNumber numberWithUnsignedInteger:0], nil]];
            state[i] = 1;
            while ([stack count] > 0) {
                NSArray *frame = [stack lastObject];
                NSUInteger node = [[frame objectAtIndex:0] unsignedIntegerValue];
                NSUInteger next = [[frame objectAtIndex:1] unsignedIntegerValue];
                NSArray *out = [successors objectAtIndex:node];
                if (next >= [out count]) {
                    state[node] = 2;
                    [stack removeLastObject];
                    continue;
                }
                [stack replaceObjectAtIndex:[stack count] - 1
                                 withObject:[NSArray arrayWithObjects:[frame objectAtIndex:0], [NSNumber numberWithUnsignedInteger:next + 1], nil]];
                NSUInteger target = [[out objectAtIndex:next] unsignedIntegerValue];
                if (state[target] == 1) {
                    // Mark the first link node->target as reversed.
                    NSUInteger linkIndex = 0;
                    for (; linkIndex < [links count]; linkIndex++) {
                        NSArray *link = [links objectAtIndex:linkIndex];
                        if ([[link objectAtIndex:0] unsignedIntegerValue] == node &&
                            [[link objectAtIndex:1] unsignedIntegerValue] == target &&
                            ![reversed containsIndex:linkIndex]) {
                            [reversed addIndex:linkIndex];
                            break;
                        }
                    }
                } else if (state[target] == 0) {
                    state[target] = 1;
                    [stack addObject:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:target], [NSNumber numberWithUnsignedInteger:0], nil]];
                }
            }
        }
        free(state);
    }

    // Longest-path ranks over the acyclic links.
    NSUInteger *rank = (NSUInteger *)calloc(count, sizeof(NSUInteger));
    {
        BOOL changed = YES;
        NSUInteger guard = 0;
        while (changed && guard++ <= count + 1) {
            changed = NO;
            NSUInteger linkIndex = 0;
            for (; linkIndex < [links count]; linkIndex++) {
                NSArray *link = [links objectAtIndex:linkIndex];
                NSUInteger from = [[link objectAtIndex:0] unsignedIntegerValue];
                NSUInteger to = [[link objectAtIndex:1] unsignedIntegerValue];
                if ([reversed containsIndex:linkIndex]) {
                    NSUInteger swap = from;
                    from = to;
                    to = swap;
                }
                if (rank[to] < rank[from] + 1) {
                    rank[to] = rank[from] + 1;
                    changed = YES;
                }
            }
        }
    }
    NSUInteger rankCount = 0;
    for (i = 0; i < count; i++) {
        rankCount = MAX(rankCount, rank[i] + 1);
    }

    // Real node sizes.
    BOOL vertical = ([flowchart direction] == OMMermaidFlowDirectionTopDown ||
                     [flowchart direction] == OMMermaidFlowDirectionBottomUp);
    NSMutableArray *texts = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray *sizeValues = [NSMutableArray array];
    for (i = 0; i < count; i++) {
        OMMermaidFlowNode *node = [nodes objectAtIndex:i];
        NSString *text = OMMermaidFlowDisplayText([node label]);
        [texts addObject:text];
        NSSize textSize = [measurer mermaidFlowSizeForNodeLabel:text];
        CGFloat width = MAX(OMFlowMinimumNodeWidth, textSize.width + 2.0 * OMFlowNodePaddingX);
        CGFloat height = textSize.height + 2.0 * OMFlowNodePaddingY;
        switch ([node shape]) {
            case OMMermaidFlowNodeShapeDiamond:
                width = textSize.width * 1.5 + 2.0 * OMFlowNodePaddingX;
                height = textSize.height * 1.5 + 2.0 * OMFlowNodePaddingY + 10.0;
                break;
            case OMMermaidFlowNodeShapeCircle:
                width = MAX(width, height + 8.0);
                height = width;
                break;
            case OMMermaidFlowNodeShapeStadium:
                width += height / 2.0;
                break;
            case OMMermaidFlowNodeShapeSubroutine:
                width += 16.0;
                break;
            default:
                break;
        }
        [sizeValues addObject:[NSValue valueWithSize:NSMakeSize(ceil(width), ceil(height))]];
    }

    // Each edge becomes a chain of nodes one rank apart: links spanning several
    // ranks (and reversed back links) get small waypoint nodes in between, so
    // ordering and spacing route them around the nodes they would cross. A
    // labelled chain's middle waypoint is sized to carry the label.
    NSMutableArray *rankOf = [NSMutableArray array];
    for (i = 0; i < count; i++) {
        [rankOf addObject:[NSNumber numberWithUnsignedInteger:rank[i]]];
    }
    NSMutableArray *chains = [NSMutableArray array];       // per edge: NSArray of node indices, or [NSNull null]
    NSMutableArray *chainReversed = [NSMutableArray array];
    NSMutableArray *labelNode = [NSMutableArray array];    // per edge: waypoint index carrying the label, or -1
    NSMutableArray *labelSizes = [NSMutableArray array];
    for (OMMermaidFlowEdge *edge in [flowchart edges]) {
        NSSize labelSize = NSZeroSize;
        if ([edge label] != nil) {
            labelSize = [measurer mermaidFlowSizeForEdgeLabel:OMMermaidFlowDisplayText([edge label])];
            labelSize.width += 2.0 * OMFlowLabelPadding;
            labelSize.height += 2.0 * OMFlowLabelPadding;
        }
        [labelSizes addObject:[NSValue valueWithSize:labelSize]];
        NSNumber *fromNumber = [indexOf objectForKey:[edge fromIdentifier]];
        NSNumber *toNumber = [indexOf objectForKey:[edge toIdentifier]];
        if (fromNumber == nil || toNumber == nil || [fromNumber isEqual:toNumber]) {
            [chains addObject:[NSNull null]];
            [chainReversed addObject:[NSNumber numberWithBool:NO]];
            [labelNode addObject:[NSNumber numberWithInteger:-1]];
            continue;
        }
        NSUInteger from = [fromNumber unsignedIntegerValue];
        NSUInteger to = [toNumber unsignedIntegerValue];
        BOOL backwards = rank[from] > rank[to];
        NSUInteger low = backwards ? to : from;
        NSUInteger high = backwards ? from : to;
        NSMutableArray *chain = [NSMutableArray arrayWithObject:[NSNumber numberWithUnsignedInteger:low]];
        NSUInteger r = rank[low] + 1;
        NSUInteger firstWaypoint = [sizeValues count];
        for (; r < rank[high]; r++) {
            [chain addObject:[NSNumber numberWithUnsignedInteger:[sizeValues count]]];
            [rankOf addObject:[NSNumber numberWithUnsignedInteger:r]];
            [sizeValues addObject:[NSValue valueWithSize:NSMakeSize(6.0, 6.0)]];
        }
        [chain addObject:[NSNumber numberWithUnsignedInteger:high]];
        NSInteger carrier = -1;
        NSUInteger waypoints = [chain count] - 2;
        if ([edge label] != nil && waypoints > 0) {
            carrier = (NSInteger)(firstWaypoint + waypoints / 2);
            [sizeValues replaceObjectAtIndex:(NSUInteger)carrier withObject:[NSValue valueWithSize:labelSize]];
        }
        [chains addObject:chain];
        [chainReversed addObject:[NSNumber numberWithBool:backwards]];
        [labelNode addObject:[NSNumber numberWithInteger:carrier]];
    }
    NSUInteger total = [sizeValues count];
    // Adjacent-rank pairs, the graph that ordering and spacing work on.
    NSMutableArray *segments = [NSMutableArray array];
    for (id chain in chains) {
        if (chain == [NSNull null]) {
            continue;
        }
        NSUInteger k = 0;
        for (; k + 1 < [chain count]; k++) {
            [segments addObject:[NSArray arrayWithObjects:[chain objectAtIndex:k], [chain objectAtIndex:k + 1], nil]];
        }
    }
    NSUInteger *allRank = (NSUInteger *)calloc(total, sizeof(NSUInteger));
    NSSize *sizes = (NSSize *)calloc(total, sizeof(NSSize));
    for (i = 0; i < total; i++) {
        allRank[i] = [[rankOf objectAtIndex:i] unsignedIntegerValue];
        sizes[i] = [[sizeValues objectAtIndex:i] sizeValue];
    }
    // Along the flow ("main") and across it ("cross").
    CGFloat (^mainSize)(NSUInteger) = ^CGFloat(NSUInteger n) { return vertical ? sizes[n].height : sizes[n].width; };
    CGFloat (^crossSize)(NSUInteger) = ^CGFloat(NSUInteger n) { return vertical ? sizes[n].width : sizes[n].height; };
    CGFloat (^gapBetween)(NSUInteger, NSUInteger) = ^CGFloat(NSUInteger a, NSUInteger b) {
        // Waypoints sit closer to their neighbours than real nodes do.
        return (a >= count || b >= count) ? OMFlowSiblingGap / 2.0 : OMFlowSiblingGap;
    };

    // Order within ranks: first mention, then barycentre sweeps.
    NSMutableArray *ranks = [NSMutableArray arrayWithCapacity:rankCount];
    for (i = 0; i < rankCount; i++) {
        [ranks addObject:[NSMutableArray array]];
    }
    for (i = 0; i < total; i++) {
        [[ranks objectAtIndex:allRank[i]] addObject:[NSNumber numberWithUnsignedInteger:i]];
    }
    CGFloat *position = (CGFloat *)calloc(total, sizeof(CGFloat));
    void (^recordPositions)(void) = ^{
        for (NSArray *row in ranks) {
            NSUInteger slot = 0;
            for (NSNumber *n in row) {
                position[[n unsignedIntegerValue]] = (CGFloat)slot++;
            }
        }
    };
    recordPositions();
    NSUInteger sweep = 0;
    for (; sweep < 6; sweep++) {
        BOOL down = (sweep % 2 == 0);
        NSInteger r = down ? 1 : (NSInteger)rankCount - 2;
        for (; down ? r < (NSInteger)rankCount : r >= 0; r += down ? 1 : -1) {
            NSMutableArray *row = [ranks objectAtIndex:(NSUInteger)r];
            NSMutableDictionary *barycentres = [NSMutableDictionary dictionary];
            for (NSNumber *n in row) {
                NSUInteger node = [n unsignedIntegerValue];
                CGFloat sum = 0.0;
                NSUInteger neighbours = 0;
                for (NSArray *segment in segments) {
                    NSUInteger a = [[segment objectAtIndex:0] unsignedIntegerValue];
                    NSUInteger b = [[segment objectAtIndex:1] unsignedIntegerValue];
                    NSUInteger other = (a == node) ? b : ((b == node) ? a : NSNotFound);
                    if (other == NSNotFound) {
                        continue;
                    }
                    if ((down && allRank[other] < allRank[node]) || (!down && allRank[other] > allRank[node])) {
                        sum += position[other];
                        neighbours += 1;
                    }
                }
                [barycentres setObject:[NSNumber numberWithDouble:(neighbours > 0 ? sum / neighbours : position[node])] forKey:n];
            }
            [row sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id first, id second) {
                return [[barycentres objectForKey:first] compare:[barycentres objectForKey:second]];
            }];
            recordPositions();
        }
    }

    // Main-axis positions: each rank as deep as its deepest member, with room
    // for labels on single-rank links leaving it.
    CGFloat *rankDepth = (CGFloat *)calloc(rankCount, sizeof(CGFloat));
    CGFloat *gapAfter = (CGFloat *)calloc(rankCount, sizeof(CGFloat));
    for (i = 0; i < total; i++) {
        rankDepth[allRank[i]] = MAX(rankDepth[allRank[i]], mainSize(i));
    }
    for (i = 0; i < rankCount; i++) {
        gapAfter[i] = OMFlowRankGap;
    }
    NSUInteger edgeIndex = 0;
    for (; edgeIndex < [chains count]; edgeIndex++) {
        id chain = [chains objectAtIndex:edgeIndex];
        NSSize labelSize = [[labelSizes objectAtIndex:edgeIndex] sizeValue];
        if (chain == [NSNull null] || labelSize.width <= 0.0 || [chain count] != 2) {
            continue;
        }
        NSUInteger low = allRank[[[chain objectAtIndex:0] unsignedIntegerValue]];
        CGFloat need = (vertical ? labelSize.height : labelSize.width) + 16.0;
        gapAfter[low] = MAX(gapAfter[low], need);
    }
    CGFloat *rankStart = (CGFloat *)calloc(rankCount, sizeof(CGFloat));
    CGFloat mainCursor = 0.0;
    for (i = 0; i < rankCount; i++) {
        rankStart[i] = mainCursor;
        mainCursor += rankDepth[i] + gapAfter[i];
    }
    CGFloat totalMain = mainCursor - (rankCount > 0 ? gapAfter[rankCount - 1] : 0.0);

    // Cross-axis positions: pull each member towards its predecessors' centres,
    // keeping order and spacing, then keep the rank balanced on those wishes.
    CGFloat *crossCenter = (CGFloat *)calloc(total, sizeof(CGFloat));
    NSUInteger r = 0;
    for (; r < rankCount; r++) {
        NSArray *row = [ranks objectAtIndex:r];
        NSUInteger rowCount = [row count];
        CGFloat *desired = (CGFloat *)calloc(rowCount, sizeof(CGFloat));
        CGFloat width = 0.0;
        NSUInteger slot = 0;
        for (; slot < rowCount; slot++) {
            NSUInteger node = [[row objectAtIndex:slot] unsignedIntegerValue];
            width += crossSize(node);
            if (slot > 0) {
                width += gapBetween([[row objectAtIndex:slot - 1] unsignedIntegerValue], node);
            }
        }
        CGFloat cursor = -width / 2.0;
        for (slot = 0; slot < rowCount; slot++) {
            NSUInteger node = [[row objectAtIndex:slot] unsignedIntegerValue];
            if (slot > 0) {
                cursor += gapBetween([[row objectAtIndex:slot - 1] unsignedIntegerValue], node);
            }
            CGFloat even = cursor + crossSize(node) / 2.0;
            cursor += crossSize(node);
            CGFloat sum = 0.0;
            NSUInteger parents = 0;
            for (NSArray *segment in segments) {
                NSUInteger a = [[segment objectAtIndex:0] unsignedIntegerValue];
                NSUInteger b = [[segment objectAtIndex:1] unsignedIntegerValue];
                NSUInteger other = (a == node) ? b : ((b == node) ? a : NSNotFound);
                if (other != NSNotFound && allRank[other] < r) {
                    sum += crossCenter[other];
                    parents += 1;
                }
            }
            desired[slot] = parents > 0 ? sum / parents : even;
        }
        CGFloat previousEnd = -INFINITY;
        NSUInteger previousNode = NSNotFound;
        CGFloat desiredSum = 0.0;
        CGFloat placedSum = 0.0;
        for (slot = 0; slot < rowCount; slot++) {
            NSUInteger node = [[row objectAtIndex:slot] unsignedIntegerValue];
            CGFloat half = crossSize(node) / 2.0;
            CGFloat gap = previousNode != NSNotFound ? gapBetween(previousNode, node) : 0.0;
            CGFloat center = MAX(desired[slot], previousEnd + gap + half);
            crossCenter[node] = center;
            previousEnd = center + half;
            previousNode = node;
            desiredSum += desired[slot];
            placedSum += center;
        }
        CGFloat shift = rowCount > 0 ? (desiredSum - placedSum) / rowCount : 0.0;
        for (slot = 0; slot < rowCount; slot++) {
            crossCenter[[[row objectAtIndex:slot] unsignedIntegerValue]] += shift;
        }
        free(desired);
    }

    // Into x/y for the flow direction.
    OMMermaidFlowDirection direction = [flowchart direction];
    NSRect *frames = (NSRect *)calloc(total, sizeof(NSRect));
    for (i = 0; i < total; i++) {
        CGFloat mainCenter = rankStart[allRank[i]] + rankDepth[allRank[i]] / 2.0;
        if (direction == OMMermaidFlowDirectionBottomUp || direction == OMMermaidFlowDirectionRightLeft) {
            mainCenter = totalMain - mainCenter;
        }
        CGFloat x = vertical ? crossCenter[i] : mainCenter;
        CGFloat y = vertical ? mainCenter : crossCenter[i];
        frames[i] = NSMakeRect(x - sizes[i].width / 2.0, y - sizes[i].height / 2.0, sizes[i].width, sizes[i].height);
    }

    // Edge polylines: outline to outline through the waypoints' centres;
    // self links loop out to the side.
    NSMutableArray *edgePoints = [NSMutableArray array];
    NSMutableArray *edgeLabels = [NSMutableArray array];
    edgeIndex = 0;
    for (OMMermaidFlowEdge *edge in [flowchart edges]) {
        id chain = [chains objectAtIndex:edgeIndex];
        NSSize labelSize = [[labelSizes objectAtIndex:edgeIndex] sizeValue];
        NSInteger carrier = [[labelNode objectAtIndex:edgeIndex] integerValue];
        BOOL backwards = [[chainReversed objectAtIndex:edgeIndex] boolValue];
        edgeIndex += 1;
        NSNumber *fromNumber = [indexOf objectForKey:[edge fromIdentifier]];
        NSArray *points = [NSArray array];
        NSPoint labelCenter = NSZeroPoint;
        if (chain == [NSNull null]) {
            if (fromNumber != nil && [[edge fromIdentifier] isEqualToString:[edge toIdentifier]]) {
                NSRect a = frames[[fromNumber unsignedIntegerValue]];
                NSPoint p1 = NSMakePoint(NSMaxX(a), NSMidY(a) - NSHeight(a) / 4.0);
                NSPoint p2 = NSMakePoint(NSMaxX(a) + OMFlowSelfLoopReach, p1.y);
                NSPoint p3 = NSMakePoint(p2.x, NSMidY(a) + NSHeight(a) / 4.0);
                NSPoint p4 = NSMakePoint(NSMaxX(a), p3.y);
                points = [NSArray arrayWithObjects:[NSValue valueWithPoint:p1], [NSValue valueWithPoint:p2],
                          [NSValue valueWithPoint:p3], [NSValue valueWithPoint:p4], nil];
                labelCenter = NSMakePoint(p2.x + labelSize.width / 2.0 + 2.0, NSMidY(a));
            }
        } else {
            NSUInteger chainCount = [chain count];
            NSMutableArray *centers = [NSMutableArray arrayWithCapacity:chainCount];
            NSUInteger k = 0;
            for (; k < chainCount; k++) {
                NSRect f = frames[[[chain objectAtIndex:k] unsignedIntegerValue]];
                [centers addObject:[NSValue valueWithPoint:NSMakePoint(NSMidX(f), NSMidY(f))]];
            }
            NSUInteger first = [[chain objectAtIndex:0] unsignedIntegerValue];
            NSUInteger last = [[chain lastObject] unsignedIntegerValue];
            NSMutableArray *path = [NSMutableArray arrayWithArray:centers];
            [path replaceObjectAtIndex:0 withObject:[NSValue valueWithPoint:
                OMFlowBoundaryPoint(frames[first], [[nodes objectAtIndex:first] shape], [[centers objectAtIndex:1] pointValue])]];
            [path replaceObjectAtIndex:chainCount - 1 withObject:[NSValue valueWithPoint:
                OMFlowBoundaryPoint(frames[last], [[nodes objectAtIndex:last] shape], [[centers objectAtIndex:chainCount - 2] pointValue])]];
            if (backwards) {
                path = [NSMutableArray arrayWithArray:[[path reverseObjectEnumerator] allObjects]];
            }
            points = path;
            if (carrier >= 0) {
                NSRect f = frames[carrier];
                labelCenter = NSMakePoint(NSMidX(f), NSMidY(f));
            } else {
                NSPoint start = [[path objectAtIndex:0] pointValue];
                NSPoint end = [[path objectAtIndex:1] pointValue];
                labelCenter = NSMakePoint((start.x + end.x) / 2.0, (start.y + end.y) / 2.0);
            }
        }
        [edgePoints addObject:points];
        NSRect labelFrame = NSZeroRect;
        if ([edge label] != nil && [points count] >= 2) {
            labelFrame = NSMakeRect(labelCenter.x - labelSize.width / 2.0, labelCenter.y - labelSize.height / 2.0,
                                    labelSize.width, labelSize.height);
        }
        [edgeLabels addObject:[NSValue valueWithRect:labelFrame]];
    }

    // Shift everything into positive space with a margin.
    CGFloat minX = INFINITY, minY = INFINITY, maxX = -INFINITY, maxY = -INFINITY;
    for (i = 0; i < count; i++) {
        minX = MIN(minX, NSMinX(frames[i]));
        minY = MIN(minY, NSMinY(frames[i]));
        maxX = MAX(maxX, NSMaxX(frames[i]));
        maxY = MAX(maxY, NSMaxY(frames[i]));
    }
    for (NSArray *points in edgePoints) {
        for (NSValue *value in points) {
            NSPoint p = [value pointValue];
            minX = MIN(minX, p.x); maxX = MAX(maxX, p.x);
            minY = MIN(minY, p.y); maxY = MAX(maxY, p.y);
        }
    }
    for (NSValue *value in edgeLabels) {
        NSRect rect = [value rectValue];
        if (NSIsEmptyRect(rect)) {
            continue;
        }
        minX = MIN(minX, NSMinX(rect)); maxX = MAX(maxX, NSMaxX(rect));
        minY = MIN(minY, NSMinY(rect)); maxY = MAX(maxY, NSMaxY(rect));
    }
    CGFloat dx = OMFlowMargin - minX;
    CGFloat dy = OMFlowMargin - minY;

    NSMutableArray *nodeLayouts = [NSMutableArray arrayWithCapacity:count];
    for (i = 0; i < count; i++) {
        NSRect frame = NSOffsetRect(frames[i], dx, dy);
        [nodeLayouts addObject:[[[OMMermaidFlowNodeLayout alloc] initWithNode:[nodes objectAtIndex:i]
                                                                         text:[texts objectAtIndex:i]
                                                                        frame:frame] autorelease]];
    }
    NSMutableArray *edgeLayouts = [NSMutableArray array];
    edgeIndex = 0;
    for (OMMermaidFlowEdge *edge in [flowchart edges]) {
        NSMutableArray *shifted = [NSMutableArray array];
        for (NSValue *value in [edgePoints objectAtIndex:edgeIndex]) {
            NSPoint p = [value pointValue];
            [shifted addObject:[NSValue valueWithPoint:NSMakePoint(p.x + dx, p.y + dy)]];
        }
        NSRect label = [[edgeLabels objectAtIndex:edgeIndex] rectValue];
        if (!NSIsEmptyRect(label)) {
            label = NSOffsetRect(label, dx, dy);
        }
        edgeIndex += 1;
        if ([shifted count] >= 2) {
            [edgeLayouts addObject:[[[OMMermaidFlowEdgeLayout alloc] initWithEdge:edge points:shifted labelFrame:label] autorelease]];
        }
    }

    OMMermaidFlowchartLayout *layout = [[[self alloc] init] autorelease];
    layout->_nodeLayouts = [nodeLayouts copy];
    layout->_edgeLayouts = [edgeLayouts copy];
    layout->_size = NSMakeSize(ceil(maxX - minX + 2.0 * OMFlowMargin), ceil(maxY - minY + 2.0 * OMFlowMargin));

    free(rank);
    free(allRank);
    free(sizes);
    free(position);
    free(rankDepth);
    free(gapAfter);
    free(rankStart);
    free(crossCenter);
    free(frames);
    return layout;
}

@end
