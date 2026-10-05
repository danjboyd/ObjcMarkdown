// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMMermaidFlowchart.h"
#import "OMMermaidFlowchartLayout.h"

// Fixed-size text, so geometry is deterministic.
@interface OMFlowFixedMeasurer : NSObject <OMMermaidFlowTextMeasuring>
@end

@implementation OMFlowFixedMeasurer
- (NSSize)mermaidFlowSizeForNodeLabel:(NSString *)label
{
    NSArray *lines = [label componentsSeparatedByString:@"\n"];
    NSUInteger longest = 0;
    for (NSString *line in lines) {
        longest = MAX(longest, [line length]);
    }
    return NSMakeSize(7.0 * longest, 16.0 * [lines count]);
}
- (NSSize)mermaidFlowSizeForEdgeLabel:(NSString *)label
{
    return NSMakeSize(6.0 * [label length], 14.0);
}
@end

@interface OMMermaidFlowchartTests : XCTestCase
@end

@implementation OMMermaidFlowchartTests

- (OMMermaidFlowchart *)parse:(NSString *)source
{
    NSError *error = nil;
    OMMermaidFlowchart *chart = [OMMermaidFlowchart flowchartWithSource:source error:&error];
    XCTAssertNotNil(chart, @"%@", error);
    return chart;
}

- (OMMermaidFlowEdge *)edgeFrom:(NSString *)from to:(NSString *)to inChart:(OMMermaidFlowchart *)chart
{
    for (OMMermaidFlowEdge *edge in [chart edges]) {
        if ([[edge fromIdentifier] isEqualToString:from] && [[edge toIdentifier] isEqualToString:to]) {
            return edge;
        }
    }
    return nil;
}

- (void)testDeclaredTypeAndDirection
{
    XCTAssertTrue([OMMermaidFlowchart sourceDeclaresFlowchart:@"%% comment\nflowchart LR\nA-->B"]);
    XCTAssertTrue([OMMermaidFlowchart sourceDeclaresFlowchart:@"graph TD;A-->B"]);
    XCTAssertFalse([OMMermaidFlowchart sourceDeclaresFlowchart:@"erDiagram\nA ||--o{ B : x"]);
    XCTAssertEqualObjects(OMMermaidDeclaredDiagramType(@"\n  sequenceDiagram\n  A->>B: hi"), @"sequenceDiagram");
    XCTAssertEqual([[self parse:@"graph RL\nA-->B"] direction], OMMermaidFlowDirectionRightLeft);
    XCTAssertEqual([[self parse:@"flowchart BT\nA-->B"] direction], OMMermaidFlowDirectionBottomUp);
    XCTAssertEqual([[self parse:@"flowchart\nA-->B"] direction], OMMermaidFlowDirectionTopDown);
}

- (void)testShapesLabelsAndLinkKinds
{
    OMMermaidFlowchart *chart = [self parse:
        @"flowchart TD\n"
         "  A[Start here] --> B(Rounded)\n"
         "  B -.-> C([Stadium]) ==> D((Circle))\n"
         "  D --- E{Decide?}\n"
         "  E -- yes --> F[[Sub]]\n"
         "  E -->|no| G[\"Quoted [text]\"]\n"
         "  F -.- G\n"];
    XCTAssertEqual([[chart nodes] count], (NSUInteger)7);
    XCTAssertEqualObjects([[chart nodeWithIdentifier:@"A"] label], @"Start here");
    XCTAssertEqual([[chart nodeWithIdentifier:@"B"] shape], OMMermaidFlowNodeShapeRounded);
    XCTAssertEqual([[chart nodeWithIdentifier:@"C"] shape], OMMermaidFlowNodeShapeStadium);
    XCTAssertEqual([[chart nodeWithIdentifier:@"D"] shape], OMMermaidFlowNodeShapeCircle);
    XCTAssertEqual([[chart nodeWithIdentifier:@"E"] shape], OMMermaidFlowNodeShapeDiamond);
    XCTAssertEqual([[chart nodeWithIdentifier:@"F"] shape], OMMermaidFlowNodeShapeSubroutine);
    XCTAssertEqualObjects([[chart nodeWithIdentifier:@"G"] label], @"Quoted [text]");

    XCTAssertEqual([[self edgeFrom:@"B" to:@"C" inChart:chart] style], OMMermaidFlowEdgeStyleDotted);
    XCTAssertEqual([[self edgeFrom:@"C" to:@"D" inChart:chart] style], OMMermaidFlowEdgeStyleThick);
    XCTAssertFalse([[self edgeFrom:@"D" to:@"E" inChart:chart] hasArrow]);
    XCTAssertTrue([[self edgeFrom:@"A" to:@"B" inChart:chart] hasArrow]);
    XCTAssertEqualObjects([[self edgeFrom:@"E" to:@"F" inChart:chart] label], @"yes");
    XCTAssertEqualObjects([[self edgeFrom:@"E" to:@"G" inChart:chart] label], @"no");
    OMMermaidFlowEdge *dottedOpen = [self edgeFrom:@"F" to:@"G" inChart:chart];
    XCTAssertEqual([dottedOpen style], OMMermaidFlowEdgeStyleDotted);
    XCTAssertFalse([dottedOpen hasArrow]);
}

- (void)testChainsGroupsAndSkippedStatements
{
    OMMermaidFlowchart *chart = [self parse:
        @"graph LR\n"
         "  classDef hot fill:#f00\n"
         "  subgraph one\n"
         "    A & B --> C --> D\n"
         "  end\n"
         "  style D fill:#0f0\n"
         "  my-node --> D; D --> A\n"];
    XCTAssertNotNil([self edgeFrom:@"A" to:@"C" inChart:chart]);
    XCTAssertNotNil([self edgeFrom:@"B" to:@"C" inChart:chart]);
    XCTAssertNotNil([self edgeFrom:@"C" to:@"D" inChart:chart]);
    XCTAssertNotNil([self edgeFrom:@"my-node" to:@"D" inChart:chart]);
    XCTAssertNotNil([self edgeFrom:@"D" to:@"A" inChart:chart]);
    XCTAssertEqual([chart skippedStatementCount], (NSUInteger)0);
    XCTAssertEqual([[chart subgraphs] count], (NSUInteger)1);
}

- (void)testSubgraphsNestAndHoldTheNodesMentionedInThem
{
    OMMermaidFlowchart *chart = [self parse:
        @"flowchart TD\n"
         "  X --> A\n"
         "  subgraph outer[\"Outer title\"]\n"
         "    A --> B\n"
         "    subgraph inner\n"
         "      C\n"
         "    end\n"
         "    B --> C\n"
         "  end\n"
         "  subgraph Some words\n"
         "    D\n"
         "  end\n"
         "  C --> outer\n"
         "  click A \"https://example.com\"\n"
         "  linkStyle 0 stroke:#f00\n"];
    NSArray *subgraphs = [chart subgraphs];
    XCTAssertEqual([subgraphs count], (NSUInteger)3);
    OMMermaidFlowSubgraph *outer = [chart subgraphWithIdentifier:@"outer"];
    OMMermaidFlowSubgraph *inner = [chart subgraphWithIdentifier:@"inner"];
    OMMermaidFlowSubgraph *words = [chart subgraphWithIdentifier:@"Some words"];
    XCTAssertEqualObjects([outer title], @"Outer title");
    XCTAssertNil([outer parentIdentifier]);
    XCTAssertEqualObjects([inner parentIdentifier], @"outer");
    XCTAssertEqualObjects([words title], @"Some words");
    // As in Mermaid, A joins outer though it was mentioned outside first;
    // C belongs to inner, the first subgraph it was mentioned in.
    XCTAssertEqualObjects([outer nodeIdentifiers], ([NSArray arrayWithObjects:@"A", @"B", nil]));
    XCTAssertEqualObjects([inner nodeIdentifiers], [NSArray arrayWithObject:@"C"]);
    XCTAssertEqualObjects([words nodeIdentifiers], [NSArray arrayWithObject:@"D"]);
    // A link to a subgraph is kept, and the subgraph isn't a node.
    XCTAssertNotNil([self edgeFrom:@"C" to:@"outer" inChart:chart]);
    XCTAssertNil([chart nodeWithIdentifier:@"outer"]);
    XCTAssertEqual([chart clickStatementCount], (NSUInteger)1);
    XCTAssertEqual([chart skippedStatementCount], (NSUInteger)2);
}

- (void)testClassDefClassAndStyleCombineInOrder
{
    OMMermaidFlowchart *chart = [self parse:
        @"flowchart LR\n"
         "  classDef default fill:#eee,stroke:#999\n"
         "  classDef hot,warm fill:rgb(255, 0, 0),color:white\n"
         "  classDef thick stroke-width:4px\n"
         "  A:::hot --> B --> C\n"
         "  class B,C thick\n"
         "  style C fill:#0f0,stroke-dasharray: 5 5\n"
         "  subgraph group\n"
         "    D\n"
         "  end\n"
         "  style group fill:none\n"];
    NSDictionary *a = [[chart nodeWithIdentifier:@"A"] styleProperties];
    XCTAssertEqualObjects([a objectForKey:@"fill"], @"rgb(255, 0, 0)");
    XCTAssertEqualObjects([a objectForKey:@"stroke"], @"#999");
    XCTAssertEqualObjects([a objectForKey:@"color"], @"white");
    NSDictionary *b = [[chart nodeWithIdentifier:@"B"] styleProperties];
    XCTAssertEqualObjects([b objectForKey:@"fill"], @"#eee");
    XCTAssertEqualObjects([b objectForKey:@"stroke-width"], @"4px");
    NSDictionary *c = [[chart nodeWithIdentifier:@"C"] styleProperties];
    XCTAssertEqualObjects([c objectForKey:@"fill"], @"#0f0");
    XCTAssertEqualObjects([c objectForKey:@"stroke-dasharray"], @"5 5");
    XCTAssertEqualObjects([[[chart subgraphWithIdentifier:@"group"] styleProperties] objectForKey:@"fill"], @"none");
}

- (void)testSubgraphFramesHoldTheirNodesAndLinksStopAtThem
{
    OMFlowFixedMeasurer *measurer = [[[OMFlowFixedMeasurer alloc] init] autorelease];
    NSArray *directions = [NSArray arrayWithObjects:@"TD", @"LR", @"BT", @"RL", nil];
    for (NSString *direction in directions) {
        OMMermaidFlowchart *chart = [self parse:[NSString stringWithFormat:
            @"flowchart %@\n"
             "  start --> A\n"
             "  start --> Z\n"
             "  subgraph one[First group]\n"
             "    A --> B\n"
             "    subgraph two\n"
             "      C\n"
             "    end\n"
             "    B --> C\n"
             "  end\n"
             "  Z --> Y\n"
             "  Y --> one\n", direction]];
        OMMermaidFlowchartLayout *layout = [OMMermaidFlowchartLayout layoutForFlowchart:chart measurer:measurer];
        XCTAssertEqual([[layout subgraphLayouts] count], (NSUInteger)2);
        NSRect one = NSZeroRect;
        NSRect two = NSZeroRect;
        for (OMMermaidFlowSubgraphLayout *group in [layout subgraphLayouts]) {
            if ([[[group subgraph] identifier] isEqualToString:@"one"]) {
                one = [group frame];
                XCTAssertTrue(NSContainsRect(one, [group titleFrame]));
            } else {
                two = [group frame];
            }
        }
        XCTAssertTrue(NSContainsRect(one, two), @"%@", direction);
        for (NSString *member in [NSArray arrayWithObjects:@"A", @"B", @"C", nil]) {
            XCTAssertTrue(NSContainsRect(one, [[layout layoutForNodeIdentifier:member] frame]), @"%@ %@", direction, member);
        }
        XCTAssertTrue(NSContainsRect(two, [[layout layoutForNodeIdentifier:@"C"] frame]), @"%@", direction);
        for (NSString *outsider in [NSArray arrayWithObjects:@"start", @"Z", @"Y", nil]) {
            XCTAssertFalse(NSIntersectsRect(one, [[layout layoutForNodeIdentifier:outsider] frame]), @"%@ %@", direction, outsider);
        }
        XCTAssertTrue(NSContainsRect(NSMakeRect(0.0, 0.0, [layout size].width, [layout size].height), one));
        // Y --> one ends on the frame's outline, not inside it.
        for (OMMermaidFlowEdgeLayout *edgeLayout in [layout edgeLayouts]) {
            if (![[[edgeLayout edge] toIdentifier] isEqualToString:@"one"]) {
                continue;
            }
            NSPoint end = [[[edgeLayout points] lastObject] pointValue];
            XCTAssertTrue(NSPointInRect(end, NSInsetRect(one, -1.0, -1.0)), @"%@", direction);
            XCTAssertFalse(NSPointInRect(end, NSInsetRect(one, 1.0, 1.0)), @"%@", direction);
        }
    }
}

- (void)testErrorsCarryLineNumbers
{
    NSError *error = nil;
    XCTAssertNil([OMMermaidFlowchart flowchartWithSource:@"flowchart TD\nA --> B\nA -->\n" error:&error]);
    XCTAssertEqualObjects([[error userInfo] objectForKey:OMMermaidFlowchartErrorLineNumberKey], @3);
    XCTAssertNil([OMMermaidFlowchart flowchartWithSource:@"flowchart TD\nA[unclosed --> B\n" error:&error]);
    XCTAssertNil([OMMermaidFlowchart flowchartWithSource:@"pie\n\"a\" : 1\n" error:&error]);
}

- (void)testLayoutFlowsAlongTheDirectionWithoutOverlaps
{
    OMFlowFixedMeasurer *measurer = [[[OMFlowFixedMeasurer alloc] init] autorelease];
    OMMermaidFlowchart *down = [self parse:@"flowchart TD\nA --> B --> C\nA --> D --> C\n"];
    OMMermaidFlowchartLayout *layout = [OMMermaidFlowchartLayout layoutForFlowchart:down measurer:measurer];
    NSRect a = [[layout layoutForNodeIdentifier:@"A"] frame];
    NSRect b = [[layout layoutForNodeIdentifier:@"B"] frame];
    NSRect c = [[layout layoutForNodeIdentifier:@"C"] frame];
    NSRect d = [[layout layoutForNodeIdentifier:@"D"] frame];
    XCTAssertTrue(NSMinY(b) > NSMaxY(a) && NSMinY(c) > NSMaxY(b));
    XCTAssertEqualWithAccuracy(NSMidY(b), NSMidY(d), 0.5, @"siblings share a rank");
    XCTAssertFalse(NSIntersectsRect(b, d));
    XCTAssertTrue(NSWidth(a) >= 56.0);

    OMMermaidFlowchart *right = [self parse:@"flowchart LR\nA --> B\n"];
    layout = [OMMermaidFlowchartLayout layoutForFlowchart:right measurer:measurer];
    XCTAssertTrue(NSMinX([[layout layoutForNodeIdentifier:@"B"] frame]) > NSMaxX([[layout layoutForNodeIdentifier:@"A"] frame]));
    OMMermaidFlowchart *left = [self parse:@"flowchart RL\nA --> B\n"];
    layout = [OMMermaidFlowchartLayout layoutForFlowchart:left measurer:measurer];
    XCTAssertTrue(NSMaxX([[layout layoutForNodeIdentifier:@"B"] frame]) < NSMinX([[layout layoutForNodeIdentifier:@"A"] frame]));
}

- (void)testEdgesEndOnNodeOutlinesAndCyclesTerminate
{
    OMFlowFixedMeasurer *measurer = [[[OMFlowFixedMeasurer alloc] init] autorelease];
    OMMermaidFlowchart *chart = [self parse:@"flowchart TD\nA --> B --> C --> A\nC --> C\nB -->|label| D\n"];
    OMMermaidFlowchartLayout *layout = [OMMermaidFlowchartLayout layoutForFlowchart:chart measurer:measurer];
    XCTAssertNotNil(layout);
    XCTAssertEqual([[layout edgeLayouts] count], (NSUInteger)5);
    for (OMMermaidFlowEdgeLayout *edgeLayout in [layout edgeLayouts]) {
        NSRect from = [[layout layoutForNodeIdentifier:[[edgeLayout edge] fromIdentifier]] frame];
        NSPoint start = [[[edgeLayout points] firstObject] pointValue];
        XCTAssertTrue(NSPointInRect(start, NSInsetRect(from, -1.0, -1.0)), @"starts on its node");
        XCTAssertFalse(NSPointInRect(start, NSInsetRect(from, 2.0, 2.0)), @"on the outline, not inside");
        if ([[edgeLayout edge] label] != nil) {
            XCTAssertFalse(NSIsEmptyRect([edgeLayout labelFrame]));
        }
    }
    XCTAssertTrue([layout size].width > 0.0 && [layout size].height > 0.0);
}

- (void)testLongAndBackEdgesRouteAroundNodesInBetween
{
    OMFlowFixedMeasurer *measurer = [[[OMFlowFixedMeasurer alloc] init] autorelease];
    OMMermaidFlowchart *chart = [self parse:@"flowchart TD\nA --> B --> C\nA -->|skip| C\nC -->|again| A\n"];
    OMMermaidFlowchartLayout *layout = [OMMermaidFlowchartLayout layoutForFlowchart:chart measurer:measurer];
    NSRect b = [[layout layoutForNodeIdentifier:@"B"] frame];
    for (OMMermaidFlowEdgeLayout *edgeLayout in [layout edgeLayouts]) {
        if ([[edgeLayout edge] label] == nil) {
            continue;
        }
        XCTAssertTrue([[edgeLayout points] count] >= 3, @"bends through a waypoint");
        for (NSValue *value in [edgeLayout points]) {
            XCTAssertFalse(NSPointInRect([value pointValue], b));
        }
        XCTAssertFalse(NSIntersectsRect([edgeLayout labelFrame], b), @"label stays visible");
    }
    OMMermaidFlowEdgeLayout *back = [[layout edgeLayouts] lastObject];
    NSRect a = [[layout layoutForNodeIdentifier:@"A"] frame];
    XCTAssertTrue(NSPointInRect([[[back points] lastObject] pointValue], NSInsetRect(a, -1.0, -1.0)), @"back edge ends at its target");
}

@end

