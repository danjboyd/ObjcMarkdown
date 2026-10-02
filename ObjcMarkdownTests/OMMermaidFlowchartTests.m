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
    XCTAssertEqual([chart skippedStatementCount], (NSUInteger)4);
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

