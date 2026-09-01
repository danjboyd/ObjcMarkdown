// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "OMMermaidERDiagram.h"
#import "OMMermaidERLayout.h"

// Fixed-width measurer. Geometry assertions stay exact across machines because
// no real font metrics enter the layout.
@interface OMMermaidTestMeasurer : NSObject <OMMermaidERTextMeasuring>
@end

@implementation OMMermaidTestMeasurer

- (CGFloat)mermaidWidthForEntityTitle:(NSString *)title
{
    return 8.0 * (CGFloat)[title length];
}

- (CGFloat)mermaidWidthForAttributeText:(NSString *)text
{
    return 7.0 * (CGFloat)[text length];
}

- (CGFloat)mermaidWidthForRelationshipLabel:(NSString *)label
{
    return 6.0 * (CGFloat)[label length];
}

@end

@interface OMMermaidERLayoutTests : XCTestCase
{
    OMMermaidTestMeasurer *_measurer;
}
@end

@implementation OMMermaidERLayoutTests

- (void)setUp
{
    [super setUp];
    _measurer = [[OMMermaidTestMeasurer alloc] init];
}

- (void)tearDown
{
    [_measurer release];
    _measurer = nil;
    [super tearDown];
}

- (OMMermaidERDiagramLayout *)layoutForSource:(NSString *)source
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram, @"source should parse: %@", error);
    return [OMMermaidERDiagramLayout layoutForDiagram:diagram
                                              metrics:[OMMermaidERLayoutMetrics defaultMetrics]
                                             measurer:_measurer];
}

- (NSString *)sampleSchemaSource
{
    return @"erDiagram\n"
            "    CUSTOMER ||--o{ ORDER : places\n"
            "    ORDER ||--|{ ORDER_ITEM : contains\n"
            "    PRODUCT ||--o{ ORDER_ITEM : \"appears in\"\n"
            "    ORDER ||--o| PAYMENT : \"settled by\"\n"
            "    CUSTOMER {\n"
            "        uuid id PK\n"
            "        text email UK\n"
            "    }\n"
            "    ORDER {\n"
            "        uuid id PK\n"
            "        uuid customer_id FK\n"
            "    }\n";
}

- (void)assertRect:(NSRect)actual equalsRect:(NSRect)expected label:(NSString *)label
{
    XCTAssertEqualWithAccuracy(actual.origin.x, expected.origin.x, 0.001, @"%@ x", label);
    XCTAssertEqualWithAccuracy(actual.origin.y, expected.origin.y, 0.001, @"%@ y", label);
    XCTAssertEqualWithAccuracy(actual.size.width, expected.size.width, 0.001, @"%@ width", label);
    XCTAssertEqualWithAccuracy(actual.size.height, expected.size.height, 0.001, @"%@ height", label);
}

#pragma mark - Golden geometry

- (void)testGoldenGeometryForTwoEntitiesAndOneRelationship
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : has\n"];
    XCTAssertNotNil(layout);

    // Both boxes fall back to the minimum width; the ranks are one gap apart.
    [self assertRect:[[layout layoutForEntityNamed:@"A"] frame]
          equalsRect:NSMakeRect(12.0, 12.0, 90.0, 26.0)
               label:@"A"];
    [self assertRect:[[layout layoutForEntityNamed:@"B"] frame]
          equalsRect:NSMakeRect(12.0, 94.0, 90.0, 26.0)
               label:@"B"];

    OMMermaidEREdgeLayout *edge = [[layout edgeLayouts] objectAtIndex:0];
    XCTAssertEqual([[edge points] count], (NSUInteger)2,
                   @"aligned boxes should route as a single straight segment");
    XCTAssertEqualWithAccuracy([edge startPoint].x, 57.0, 0.001);
    XCTAssertEqualWithAccuracy([edge startPoint].y, 38.0, 0.001);
    XCTAssertEqualWithAccuracy([edge endPoint].x, 57.0, 0.001);
    XCTAssertEqualWithAccuracy([edge endPoint].y, 94.0, 0.001);

    [self assertRect:[edge labelFrame]
          equalsRect:NSMakeRect(61.0, 49.0, 26.0, 14.0)
               label:@"label"];

    XCTAssertEqualWithAccuracy([layout size].width, 114.0, 0.001);
    XCTAssertEqualWithAccuracy([layout size].height, 132.0, 0.001);
}

- (void)testGoldenColumnGeometryForAttributeRows
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : \"\"\n"
         "    A {\n"
         "        uuid id PK\n"
         "        text email\n"
         "    }\n"];
    XCTAssertNotNil(layout);

    OMMermaidEREntityLayout *entity = [layout layoutForEntityNamed:@"A"];
    NSRect frame = [entity frame];
    // 8 padding + 28 type + 10 gap + 35 name + 10 gap + 14 key + 8 padding.
    XCTAssertEqualWithAccuracy(frame.size.width, 113.0, 0.001);
    XCTAssertEqualWithAccuracy(frame.size.height, 62.0, 0.001);
    [self assertRect:[entity titleFrame]
          equalsRect:NSMakeRect(frame.origin.x, frame.origin.y, 113.0, 26.0)
               label:@"title"];

    NSArray *rows = [entity attributeRows];
    XCTAssertEqual([rows count], (NSUInteger)2);

    OMMermaidERAttributeRowLayout *first = [rows objectAtIndex:0];
    CGFloat rowY = frame.origin.y + 26.0;
    [self assertRect:[first frame]
          equalsRect:NSMakeRect(frame.origin.x, rowY, 113.0, 18.0)
               label:@"row 0"];
    [self assertRect:[first typeFrame]
          equalsRect:NSMakeRect(frame.origin.x + 8.0, rowY, 28.0, 18.0)
               label:@"type 0"];
    [self assertRect:[first nameFrame]
          equalsRect:NSMakeRect(frame.origin.x + 46.0, rowY, 35.0, 18.0)
               label:@"name 0"];
    [self assertRect:[first keyFrame]
          equalsRect:NSMakeRect(frame.origin.x + 91.0, rowY, 14.0, 18.0)
               label:@"key 0"];

    // The second attribute has no key marker, so its key cell is empty but stays
    // in the column so drawing code can rely on the position.
    OMMermaidERAttributeRowLayout *second = [rows objectAtIndex:1];
    XCTAssertEqualWithAccuracy([second keyFrame].origin.x, frame.origin.x + 91.0, 0.001);
    XCTAssertEqualWithAccuracy([second keyFrame].size.width, 0.0, 0.001);
    XCTAssertEqualWithAccuracy([second commentFrame].size.width, 0.0, 0.001);
}

- (void)testCommentColumnWidensTheBox
{
    OMMermaidERDiagramLayout *withComment = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : x\n"
         "    A {\n"
         "        uuid identifier PK \"the key\"\n"
         "    }\n"];
    OMMermaidERDiagramLayout *withoutComment = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : x\n"
         "    A {\n"
         "        uuid identifier PK\n"
         "    }\n"];

    CGFloat wide = [[withComment layoutForEntityNamed:@"A"] frame].size.width;
    CGFloat narrow = [[withoutComment layoutForEntityNamed:@"A"] frame].size.width;
    // 10 gap + "the key" at 7 points per character.
    XCTAssertEqualWithAccuracy(wide - narrow, 59.0, 0.001);
}

#pragma mark - Ranking and ordering

- (void)testBusiestEntityAnchorsTheTopRank
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : x\n"
         "    B ||--o{ C : y\n"];

    XCTAssertEqual([[layout layoutForEntityNamed:@"B"] rank], (NSUInteger)0);
    XCTAssertEqual([[layout layoutForEntityNamed:@"A"] rank], (NSUInteger)1);
    XCTAssertEqual([[layout layoutForEntityNamed:@"C"] rank], (NSUInteger)1);
}

- (void)testRankMatchesBreadthFirstDistanceFromTheHub
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];
    XCTAssertNotNil(layout);

    // ORDER has the highest degree, so it anchors rank 0.
    XCTAssertEqual([[layout layoutForEntityNamed:@"ORDER"] rank], (NSUInteger)0);
    XCTAssertEqual([[layout layoutForEntityNamed:@"CUSTOMER"] rank], (NSUInteger)1);
    XCTAssertEqual([[layout layoutForEntityNamed:@"ORDER_ITEM"] rank], (NSUInteger)1);
    XCTAssertEqual([[layout layoutForEntityNamed:@"PAYMENT"] rank], (NSUInteger)1);
    XCTAssertEqual([[layout layoutForEntityNamed:@"PRODUCT"] rank], (NSUInteger)2);
}

- (void)testOrderInRankIsContiguousAndMatchesHorizontalOrder
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];

    NSMutableDictionary *byRank = [NSMutableDictionary dictionary];
    for (OMMermaidEREntityLayout *entity in [layout entityLayouts]) {
        NSNumber *key = [NSNumber numberWithUnsignedInteger:[entity rank]];
        NSMutableArray *bucket = [byRank objectForKey:key];
        if (bucket == nil) {
            bucket = [NSMutableArray array];
            [byRank setObject:bucket forKey:key];
        }
        [bucket addObject:entity];
    }

    for (NSNumber *key in byRank) {
        NSArray *bucket = [byRank objectForKey:key];
        NSMutableArray *seenOrders = [NSMutableArray array];
        for (OMMermaidEREntityLayout *entity in bucket) {
            [seenOrders addObject:[NSNumber numberWithUnsignedInteger:[entity orderInRank]]];
        }
        NSArray *sortedOrders = [seenOrders sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger index = 0;
        for (; index < [sortedOrders count]; index++) {
            XCTAssertEqual([[sortedOrders objectAtIndex:index] unsignedIntegerValue], index,
                           @"orderInRank must be contiguous from zero within a rank");
        }

        for (OMMermaidEREntityLayout *first in bucket) {
            for (OMMermaidEREntityLayout *second in bucket) {
                if ([first orderInRank] >= [second orderInRank]) {
                    continue;
                }
                XCTAssertTrue(NSMaxX([first frame]) <= NSMinX([second frame]),
                              @"a lower orderInRank must sit further left");
            }
        }
    }
}

- (void)testDisconnectedComponentsShareRankRows
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : x\n"
         "    C ||--o{ D : y\n"];

    XCTAssertEqual([[layout layoutForEntityNamed:@"A"] rank], (NSUInteger)0);
    XCTAssertEqual([[layout layoutForEntityNamed:@"C"] rank], (NSUInteger)0);
    XCTAssertEqual([[layout layoutForEntityNamed:@"B"] rank], (NSUInteger)1);
    XCTAssertEqual([[layout layoutForEntityNamed:@"D"] rank], (NSUInteger)1);
    XCTAssertTrue(NSMaxX([[layout layoutForEntityNamed:@"A"] frame]) <=
                  NSMinX([[layout layoutForEntityNamed:@"C"] frame]));
}

#pragma mark - Placement invariants

- (void)testBoxesInTheSameRankDoNotOverlap
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];

    for (OMMermaidEREntityLayout *first in [layout entityLayouts]) {
        for (OMMermaidEREntityLayout *second in [layout entityLayouts]) {
            if (first == second) {
                continue;
            }
            XCTAssertFalse(NSIntersectsRect([first frame], [second frame]),
                           @"%@ overlaps %@", [first entity], [second entity]);
        }
    }
}

- (void)testHigherRanksSitBelowLowerRanks
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];

    for (OMMermaidEREntityLayout *first in [layout entityLayouts]) {
        for (OMMermaidEREntityLayout *second in [layout entityLayouts]) {
            if ([first rank] >= [second rank]) {
                continue;
            }
            XCTAssertTrue(NSMaxY([first frame]) < NSMinY([second frame]),
                          @"rank %lu must sit above rank %lu",
                          (unsigned long)[first rank],
                          (unsigned long)[second rank]);
        }
    }
}

- (void)testEverythingFitsInsideTheReportedSize
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];
    NSRect bounds = NSMakeRect(0.0, 0.0, [layout size].width, [layout size].height);

    for (OMMermaidEREntityLayout *entity in [layout entityLayouts]) {
        XCTAssertTrue(NSContainsRect(bounds, [entity frame]),
                      @"%@ escapes the diagram bounds", [entity entity]);
    }
    for (OMMermaidEREdgeLayout *edge in [layout edgeLayouts]) {
        for (NSValue *value in [edge points]) {
            NSPoint point = [value pointValue];
            XCTAssertTrue(NSPointInRect(point, bounds), @"edge point escapes the bounds");
        }
        if (!NSIsEmptyRect([edge labelFrame])) {
            XCTAssertTrue(NSContainsRect(bounds, [edge labelFrame]),
                          @"label escapes the diagram bounds");
        }
    }
}

#pragma mark - Edge routing

- (void)testEdgePolylinesAreOrthogonal
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];

    for (OMMermaidEREdgeLayout *edge in [layout edgeLayouts]) {
        NSArray *points = [edge points];
        XCTAssertTrue([points count] >= 2);
        NSUInteger index = 1;
        for (; index < [points count]; index++) {
            NSPoint previous = [[points objectAtIndex:index - 1] pointValue];
            NSPoint current = [[points objectAtIndex:index] pointValue];
            BOOL orthogonal = (fabs(previous.x - current.x) < 0.001) ||
                              (fabs(previous.y - current.y) < 0.001);
            XCTAssertTrue(orthogonal, @"segment %lu is diagonal", (unsigned long)index);
        }
    }
}

- (void)testEdgeEndpointsLandOnTheirOwnEntityBoxes
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];

    for (OMMermaidEREdgeLayout *edge in [layout edgeLayouts]) {
        OMMermaidEREntityLayout *left =
            [layout layoutForEntityNamed:[[edge relationship] leftEntityName]];
        OMMermaidEREntityLayout *right =
            [layout layoutForEntityNamed:[[edge relationship] rightEntityName]];
        XCTAssertNotNil(left);
        XCTAssertNotNil(right);

        NSPoint start = [edge startPoint];
        XCTAssertTrue(start.x > NSMinX([left frame]) && start.x < NSMaxX([left frame]),
                      @"start point must sit within the left entity box");
        XCTAssertTrue(fabs(start.y - NSMinY([left frame])) < 0.001 ||
                      fabs(start.y - NSMaxY([left frame])) < 0.001,
                      @"start point must sit on a horizontal edge of the left box");

        NSPoint end = [edge endPoint];
        XCTAssertTrue(end.x > NSMinX([right frame]) && end.x < NSMaxX([right frame]),
                      @"end point must sit within the right entity box");
        XCTAssertTrue(fabs(end.y - NSMinY([right frame])) < 0.001 ||
                      fabs(end.y - NSMaxY([right frame])) < 0.001,
                      @"end point must sit on a horizontal edge of the right box");
    }
}

- (void)testParallelRelationshipsGetSeparateAttachmentPoints
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : first\n"
         "    A ||--o{ B : second\n"];

    NSArray *edges = [layout edgeLayouts];
    XCTAssertEqual([edges count], (NSUInteger)2);

    OMMermaidEREdgeLayout *first = [edges objectAtIndex:0];
    OMMermaidEREdgeLayout *second = [edges objectAtIndex:1];
    XCTAssertTrue(fabs([first startPoint].x - [second startPoint].x) > 0.001,
                  @"parallel edges must leave their entity at different points");
    XCTAssertTrue(fabs([first endPoint].x - [second endPoint].x) > 0.001,
                  @"parallel edges must arrive at different points");
    XCTAssertTrue(fabs(NSMinX([first labelFrame]) - NSMinX([second labelFrame])) > 0.001,
                  @"parallel edge labels must not stack on each other");
}

- (void)testEdgesSharingAGapUseSeparateLanes
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    HUB ||--o{ A : x\n"
         "    HUB ||--o{ B : y\n"];

    NSArray *edges = [layout edgeLayouts];
    OMMermaidEREdgeLayout *first = [edges objectAtIndex:0];
    OMMermaidEREdgeLayout *second = [edges objectAtIndex:1];
    XCTAssertEqual([[first points] count], (NSUInteger)4);
    XCTAssertEqual([[second points] count], (NSUInteger)4);

    CGFloat firstLane = [[[first points] objectAtIndex:1] pointValue].y;
    CGFloat secondLane = [[[second points] objectAtIndex:1] pointValue].y;
    XCTAssertTrue(fabs(firstLane - secondLane) > 0.001,
                  @"edges crossing the same gap must not share a horizontal run");
}

- (void)testSameRankRelationshipDipsBelowBothBoxes
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    HUB ||--o{ A : x\n"
         "    HUB ||--o{ B : y\n"
         "    A ||--o{ B : sibling\n"];

    OMMermaidEREntityLayout *a = [layout layoutForEntityNamed:@"A"];
    OMMermaidEREntityLayout *b = [layout layoutForEntityNamed:@"B"];
    XCTAssertEqual([a rank], [b rank]);

    OMMermaidEREdgeLayout *sibling = [[layout edgeLayouts] objectAtIndex:2];
    XCTAssertEqualObjects([[sibling relationship] label], @"sibling");
    XCTAssertEqual([[sibling points] count], (NSUInteger)4);

    CGFloat laneY = [[[sibling points] objectAtIndex:1] pointValue].y;
    XCTAssertTrue(laneY > NSMaxY([a frame]), @"same-rank edges route below their rank");
    XCTAssertTrue(laneY > NSMaxY([b frame]));
    XCTAssertEqualWithAccuracy([sibling startPoint].y, NSMaxY([a frame]), 0.001);
    XCTAssertEqualWithAccuracy([sibling endPoint].y, NSMaxY([b frame]), 0.001);
}

- (void)testSelfRelationshipGetsTwoDistinctAttachmentPoints
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    NODE ||--o{ NODE : \"reports to\"\n"];
    XCTAssertNotNil(layout);

    OMMermaidEREdgeLayout *edge = [[layout edgeLayouts] objectAtIndex:0];
    XCTAssertTrue(fabs([edge startPoint].x - [edge endPoint].x) > 0.001,
                  @"a self relationship must leave and re-enter at different points");
    XCTAssertEqual([[edge points] count], (NSUInteger)4);
}

- (void)testUnlabeledRelationshipHasNoLabelFrame
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:
        @"erDiagram\n"
         "    A ||--o{ B : \"\"\n"];
    XCTAssertTrue(NSIsEmptyRect([[[layout edgeLayouts] objectAtIndex:0] labelFrame]));
}

- (void)testEdgeLayoutsMatchRelationshipOrder
{
    OMMermaidERDiagramLayout *layout = [self layoutForSource:[self sampleSchemaSource]];
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:[self sampleSchemaSource]
                                                                 error:&error];

    XCTAssertEqual([[layout edgeLayouts] count], [[diagram relationships] count]);
    NSUInteger index = 0;
    for (; index < [[layout edgeLayouts] count]; index++) {
        OMMermaidERRelationship *expected = [[diagram relationships] objectAtIndex:index];
        OMMermaidERRelationship *actual = [[[layout edgeLayouts] objectAtIndex:index] relationship];
        XCTAssertEqualObjects([actual leftEntityName], [expected leftEntityName]);
        XCTAssertEqualObjects([actual rightEntityName], [expected rightEntityName]);
        XCTAssertEqualObjects([actual label], [expected label]);
    }
}

#pragma mark - Determinism and limits

- (void)testLayoutIsDeterministic
{
    OMMermaidERDiagramLayout *first = [self layoutForSource:[self sampleSchemaSource]];
    OMMermaidERDiagramLayout *second = [self layoutForSource:[self sampleSchemaSource]];

    XCTAssertEqualWithAccuracy([first size].width, [second size].width, 0.0001);
    XCTAssertEqualWithAccuracy([first size].height, [second size].height, 0.0001);

    NSUInteger index = 0;
    for (; index < [[first entityLayouts] count]; index++) {
        OMMermaidEREntityLayout *a = [[first entityLayouts] objectAtIndex:index];
        OMMermaidEREntityLayout *b = [[second entityLayouts] objectAtIndex:index];
        XCTAssertEqualObjects([[a entity] name], [[b entity] name]);
        XCTAssertEqual([a rank], [b rank]);
        XCTAssertEqual([a orderInRank], [b orderInRank]);
        [self assertRect:[a frame] equalsRect:[b frame] label:[[a entity] name]];
    }

    for (index = 0; index < [[first edgeLayouts] count]; index++) {
        NSArray *pointsA = [[[first edgeLayouts] objectAtIndex:index] points];
        NSArray *pointsB = [[[second edgeLayouts] objectAtIndex:index] points];
        XCTAssertEqualObjects(pointsA, pointsB);
    }
}

- (void)testLayoutRefusesDiagramsBeyondTheEntityLimit
{
    NSMutableString *source = [NSMutableString stringWithString:@"erDiagram\n"];
    NSUInteger index = 0;
    for (; index <= OMMermaidERLayoutMaximumEntities; index++) {
        [source appendFormat:@"    E%lu\n", (unsigned long)index];
    }

    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertTrue([[diagram entities] count] > OMMermaidERLayoutMaximumEntities);
    XCTAssertNil([OMMermaidERDiagramLayout layoutForDiagram:diagram
                                                    metrics:nil
                                                   measurer:_measurer]);
}

- (void)testLayoutRequiresADiagramAndAMeasurer
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:[self sampleSchemaSource]
                                                                 error:&error];
    XCTAssertNil([OMMermaidERDiagramLayout layoutForDiagram:nil metrics:nil measurer:_measurer]);
    XCTAssertNil([OMMermaidERDiagramLayout layoutForDiagram:diagram metrics:nil measurer:nil]);
    XCTAssertNotNil([OMMermaidERDiagramLayout layoutForDiagram:diagram metrics:nil measurer:_measurer]);
}

- (void)testMetricsCopyIsIndependent
{
    OMMermaidERLayoutMetrics *metrics = [OMMermaidERLayoutMetrics defaultMetrics];
    [metrics setRankSpacing:100.0];
    OMMermaidERLayoutMetrics *copy = [[metrics copy] autorelease];
    [copy setRankSpacing:200.0];

    XCTAssertEqualWithAccuracy([metrics rankSpacing], 100.0, 0.001);
    XCTAssertEqualWithAccuracy([copy rankSpacing], 200.0, 0.001);
    XCTAssertEqualWithAccuracy([copy titleHeight], [metrics titleHeight], 0.001);
}

- (void)testRankSpacingMetricChangesVerticalSeparation
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:
        @"erDiagram\n"
         "    A ||--o{ B : x\n" error:&error];

    OMMermaidERLayoutMetrics *metrics = [OMMermaidERLayoutMetrics defaultMetrics];
    [metrics setRankSpacing:200.0];
    OMMermaidERDiagramLayout *layout = [OMMermaidERDiagramLayout layoutForDiagram:diagram
                                                                         metrics:metrics
                                                                        measurer:_measurer];

    CGFloat separation = NSMinY([[layout layoutForEntityNamed:@"B"] frame]) -
                         NSMaxY([[layout layoutForEntityNamed:@"A"] frame]);
    XCTAssertEqualWithAccuracy(separation, 200.0, 0.001);
}

@end
