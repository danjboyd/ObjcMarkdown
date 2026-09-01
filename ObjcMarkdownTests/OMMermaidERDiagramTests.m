// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "OMMermaidERDiagram.h"

@interface OMMermaidERDiagramTests : XCTestCase
@end

@implementation OMMermaidERDiagramTests

- (NSString *)sampleSchemaSource
{
    return @"erDiagram\n"
            "    CUSTOMER ||--o{ ORDER : places\n"
            "    ORDER ||--|{ ORDER_ITEM : contains\n"
            "    ORDER ||--o| PAYMENT : \"settled by\"\n"
            "\n"
            "    CUSTOMER {\n"
            "        uuid id PK\n"
            "        text email UK\n"
            "        text full_name\n"
            "    }\n"
            "    ORDER {\n"
            "        uuid id PK\n"
            "        uuid customer_id FK\n"
            "        numeric total_cents\n"
            "    }\n";
}

- (NSUInteger)errorLineNumberForSource:(NSString *)source
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNil(diagram);
    XCTAssertNotNil(error);
    NSNumber *lineNumber = [[error userInfo] objectForKey:OMMermaidERDiagramErrorLineNumberKey];
    return lineNumber != nil ? [lineNumber unsignedIntegerValue] : 0;
}

- (NSInteger)errorCodeForSource:(NSString *)source
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNil(diagram);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([error domain], OMMermaidERDiagramErrorDomain);
    return [error code];
}

#pragma mark - Detection

- (void)testSourceDeclaresERDiagramAcceptsHeaderAfterBlanksAndComments
{
    NSString *source = @"\n"
                        "%% a comment\n"
                        "erDiagram\n"
                        "    A ||--|| B : x\n";
    XCTAssertTrue([OMMermaidERDiagram sourceDeclaresERDiagram:source]);
}

- (void)testSourceDeclaresERDiagramRejectsOtherDiagramTypes
{
    XCTAssertFalse([OMMermaidERDiagram sourceDeclaresERDiagram:@"flowchart LR\n  A --> B\n"]);
    XCTAssertFalse([OMMermaidERDiagram sourceDeclaresERDiagram:@"sequenceDiagram\n  A->>B: hi\n"]);
    XCTAssertFalse([OMMermaidERDiagram sourceDeclaresERDiagram:@""]);
    XCTAssertFalse([OMMermaidERDiagram sourceDeclaresERDiagram:nil]);
}

- (void)testSourceDeclaresERDiagramRejectsTrailingTextOnHeaderLine
{
    XCTAssertFalse([OMMermaidERDiagram sourceDeclaresERDiagram:@"erDiagram title Schema\n"]);
}

#pragma mark - Structure

- (void)testParsesEntitiesRelationshipsAndAttributes
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:[self sampleSchemaSource]
                                                                 error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertNil(error);

    XCTAssertEqual([[diagram entities] count], (NSUInteger)4);
    XCTAssertEqual([[diagram relationships] count], (NSUInteger)3);

    OMMermaidEREntity *customer = [diagram entityNamed:@"CUSTOMER"];
    XCTAssertNotNil(customer);
    XCTAssertEqualObjects([customer displayName], @"CUSTOMER");
    XCTAssertEqual([[customer attributes] count], (NSUInteger)3);

    OMMermaidERAttribute *identifier = [[customer attributes] objectAtIndex:0];
    XCTAssertEqualObjects([identifier type], @"uuid");
    XCTAssertEqualObjects([identifier name], @"id");
    XCTAssertEqualObjects([identifier keys], [NSArray arrayWithObject:@"PK"]);
    XCTAssertNil([identifier comment]);

    OMMermaidERAttribute *fullName = [[customer attributes] objectAtIndex:2];
    XCTAssertEqualObjects([fullName name], @"full_name");
    XCTAssertEqual([[fullName keys] count], (NSUInteger)0);
}

- (void)testEntitiesAreOrderedByFirstAppearance
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:[self sampleSchemaSource]
                                                                 error:&error];
    XCTAssertNotNil(diagram);

    NSMutableArray *names = [NSMutableArray array];
    for (OMMermaidEREntity *entity in [diagram entities]) {
        [names addObject:[entity name]];
    }

    NSArray *expected = [NSArray arrayWithObjects:
        @"CUSTOMER", @"ORDER", @"ORDER_ITEM", @"PAYMENT", nil];
    XCTAssertEqualObjects([names subarrayWithRange:NSMakeRange(0, [expected count])], expected);
}

- (void)testEntityReferencedOnlyByRelationshipHasNoAttributes
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:[self sampleSchemaSource]
                                                                 error:&error];
    OMMermaidEREntity *payment = [diagram entityNamed:@"PAYMENT"];
    XCTAssertNotNil(payment);
    XCTAssertEqual([[payment attributes] count], (NSUInteger)0);
}

- (void)testStandaloneEntityStatementCreatesEntity
{
    NSString *source = @"erDiagram\n"
                        "    ORPHAN\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertEqual([[diagram entities] count], (NSUInteger)1);
    XCTAssertNotNil([diagram entityNamed:@"ORPHAN"]);
}

- (void)testRepeatedEntityBlocksAppendAttributes
{
    NSString *source = @"erDiagram\n"
                        "    A {\n"
                        "        int one\n"
                        "    }\n"
                        "    A {\n"
                        "        int two\n"
                        "    }\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertEqual([[diagram entities] count], (NSUInteger)1);
    XCTAssertEqual([[[diagram entityNamed:@"A"] attributes] count], (NSUInteger)2);
}

#pragma mark - Cardinality

- (void)testParsesEveryCardinalityMarkerPair
{
    NSString *source = @"erDiagram\n"
                        "    A |o--o| B : a\n"
                        "    C ||--|| D : b\n"
                        "    E }o--o{ F : c\n"
                        "    G }|--|{ H : d\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);

    NSArray *relationships = [diagram relationships];
    XCTAssertEqual([relationships count], (NSUInteger)4);

    OMMermaidERRelationship *zeroOrOne = [relationships objectAtIndex:0];
    XCTAssertEqual([zeroOrOne leftCardinality], OMMermaidERCardinalityZeroOrOne);
    XCTAssertEqual([zeroOrOne rightCardinality], OMMermaidERCardinalityZeroOrOne);

    OMMermaidERRelationship *exactlyOne = [relationships objectAtIndex:1];
    XCTAssertEqual([exactlyOne leftCardinality], OMMermaidERCardinalityExactlyOne);
    XCTAssertEqual([exactlyOne rightCardinality], OMMermaidERCardinalityExactlyOne);

    OMMermaidERRelationship *zeroOrMore = [relationships objectAtIndex:2];
    XCTAssertEqual([zeroOrMore leftCardinality], OMMermaidERCardinalityZeroOrMore);
    XCTAssertEqual([zeroOrMore rightCardinality], OMMermaidERCardinalityZeroOrMore);

    OMMermaidERRelationship *oneOrMore = [relationships objectAtIndex:3];
    XCTAssertEqual([oneOrMore leftCardinality], OMMermaidERCardinalityOneOrMore);
    XCTAssertEqual([oneOrMore rightCardinality], OMMermaidERCardinalityOneOrMore);
}

- (void)testNonIdentifyingConnectorIsRecognized
{
    NSString *source = @"erDiagram\n"
                        "    A ||..o{ B : soft\n"
                        "    C ||--o{ D : hard\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertFalse([[[diagram relationships] objectAtIndex:0] isIdentifying]);
    XCTAssertTrue([[[diagram relationships] objectAtIndex:1] isIdentifying]);
}

#pragma mark - Labels, quoting, aliases

- (void)testQuotedRelationshipLabelKeepsSpaces
{
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:[self sampleSchemaSource]
                                                                 error:&error];
    OMMermaidERRelationship *payment = [[diagram relationships] objectAtIndex:2];
    XCTAssertEqualObjects([payment label], @"settled by");
    XCTAssertEqualObjects([payment rightEntityName], @"PAYMENT");
}

- (void)testEmptyQuotedLabelParsesAsEmptyString
{
    NSString *source = @"erDiagram\n"
                        "    A ||--o{ B : \"\"\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertEqualObjects([[[diagram relationships] objectAtIndex:0] label], @"");
}

- (void)testRelationshipWithoutLabelParsesAsEmptyString
{
    NSString *source = @"erDiagram\n"
                        "    A ||--o{ B\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertEqualObjects([[[diagram relationships] objectAtIndex:0] label], @"");
}

- (void)testEntityAliasBecomesDisplayName
{
    NSString *source = @"erDiagram\n"
                        "    p[Person] ||--o{ c[\"Car Loan\"] : owns\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertEqualObjects([[diagram entityNamed:@"p"] displayName], @"Person");
    XCTAssertEqualObjects([[diagram entityNamed:@"c"] displayName], @"Car Loan");
}

- (void)testEntityBlockAliasIsAppliedToEntityFromRelationship
{
    NSString *source = @"erDiagram\n"
                        "    p ||--o{ c : owns\n"
                        "    p[\"Person Record\"] {\n"
                        "        uuid id PK\n"
                        "    }\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    XCTAssertEqual([[diagram entities] count], (NSUInteger)2);
    XCTAssertEqualObjects([[diagram entityNamed:@"p"] displayName], @"Person Record");
}

- (void)testQuotedEntityNameIsNotMistakenForCardinality
{
    NSString *source = @"erDiagram\n"
                        "    \"weird||--o{name\" ||--o{ B : x\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    OMMermaidERRelationship *relationship = [[diagram relationships] objectAtIndex:0];
    XCTAssertEqualObjects([relationship leftEntityName], @"weird||--o{name");
    XCTAssertEqualObjects([relationship rightEntityName], @"B");
}

#pragma mark - Attributes

- (void)testAttributeCommentAndMultipleKeys
{
    NSString *source = @"erDiagram\n"
                        "    A {\n"
                        "        uuid order_id PK,FK \"references ORDER\"\n"
                        "        char(2) country\n"
                        "    }\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);

    NSArray *attributes = [[diagram entityNamed:@"A"] attributes];
    OMMermaidERAttribute *orderID = [attributes objectAtIndex:0];
    NSArray *expectedKeys = [NSArray arrayWithObjects:@"PK", @"FK", nil];
    XCTAssertEqualObjects([orderID keys], expectedKeys);
    XCTAssertEqualObjects([orderID comment], @"references ORDER");

    OMMermaidERAttribute *country = [attributes objectAtIndex:1];
    XCTAssertEqualObjects([country type], @"char(2)");
    XCTAssertEqualObjects([country name], @"country");
    XCTAssertNil([country comment]);
}

- (void)testSpaceSeparatedKeysAreAccepted
{
    NSString *source = @"erDiagram\n"
                        "    A {\n"
                        "        uuid id PK UK\n"
                        "    }\n";
    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:source error:&error];
    XCTAssertNotNil(diagram);
    NSArray *expectedKeys = [NSArray arrayWithObjects:@"PK", @"UK", nil];
    XCTAssertEqualObjects([[[[diagram entityNamed:@"A"] attributes] objectAtIndex:0] keys], expectedKeys);
}

#pragma mark - Failures

- (void)testMissingHeaderIsRejected
{
    NSString *source = @"flowchart LR\n  A --> B\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorMissingHeader);
}

- (void)testHeaderOnlyDiagramIsRejected
{
    XCTAssertEqual([self errorCodeForSource:@"erDiagram\n"],
                   (NSInteger)OMMermaidERDiagramErrorEmptyDiagram);
}

- (void)testUnterminatedEntityBlockIsRejectedAtOpeningLine
{
    NSString *source = @"erDiagram\n"
                        "    A ||--o{ B : x\n"
                        "    A {\n"
                        "        uuid id PK\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorUnterminatedEntityBlock);
    XCTAssertEqual([self errorLineNumberForSource:source], (NSUInteger)3);
}

- (void)testMalformedAttributeReportsItsOwnLine
{
    NSString *source = @"erDiagram\n"
                        "    A {\n"
                        "        uuid id PK\n"
                        "        lonely\n"
                        "    }\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorMalformedAttribute);
    XCTAssertEqual([self errorLineNumberForSource:source], (NSUInteger)4);
}

- (void)testUnknownAttributeKeyIsRejected
{
    NSString *source = @"erDiagram\n"
                        "    A {\n"
                        "        uuid id XX\n"
                        "    }\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorMalformedAttribute);
}

- (void)testUnterminatedAttributeCommentIsRejected
{
    NSString *source = @"erDiagram\n"
                        "    A {\n"
                        "        uuid id PK \"unterminated\n"
                        "    }\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorMalformedAttribute);
}

- (void)testTrailingTextAfterRelationshipLabelIsRejected
{
    NSString *source = @"erDiagram\n"
                        "    A ||--o{ B : \"places\" extra\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorMalformedRelationship);
}

- (void)testTextBeforeCardinalityIsRejected
{
    NSString *source = @"erDiagram\n"
                        "    A B ||--o{ C : x\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorMalformedRelationship);
}

- (void)testDirectionStatementIsRejected
{
    NSString *source = @"erDiagram\n"
                        "    direction LR\n"
                        "    A ||--o{ B : x\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorMalformedEntity);
    XCTAssertEqual([self errorLineNumberForSource:source], (NSUInteger)2);
}

- (void)testStrayClosingBraceIsRejected
{
    NSString *source = @"erDiagram\n"
                        "    A ||--o{ B : x\n"
                        "    }\n";
    XCTAssertEqual([self errorCodeForSource:source],
                   (NSInteger)OMMermaidERDiagramErrorUnsupportedStatement);
}

- (void)testNilSourceIsRejectedWithoutCrashing
{
    NSError *error = nil;
    XCTAssertNil([OMMermaidERDiagram diagramWithSource:nil error:&error]);
    XCTAssertNotNil(error);
}

- (void)testErrorOutParameterIsOptional
{
    XCTAssertNil([OMMermaidERDiagram diagramWithSource:@"not a diagram" error:NULL]);
    XCTAssertNotNil([OMMermaidERDiagram diagramWithSource:[self sampleSchemaSource] error:NULL]);
}

@end
