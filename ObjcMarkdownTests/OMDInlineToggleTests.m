// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDInlineToggle.h"

@interface OMDInlineToggleTests : XCTestCase
@end

@implementation OMDInlineToggleTests

- (NSDictionary *)editForSource:(NSString *)source
                      selection:(NSRange)selection
                         prefix:(NSString *)prefix
                         suffix:(NSString *)suffix
                    placeholder:(NSString *)placeholder
{
    NSRange replaceRange = NSMakeRange(0, 0);
    NSRange nextSelection = NSMakeRange(0, 0);
    NSString *replacement = nil;
    BOOL computed = OMDComputeInlineToggleEdit(source,
                                               selection,
                                               prefix,
                                               suffix,
                                               placeholder,
                                               &replaceRange,
                                               &replacement,
                                               &nextSelection);
    XCTAssertTrue(computed);
    XCTAssertNotNil(replacement);
    return @{
        @"replaceRange": [NSValue valueWithRange:replaceRange],
        @"replacement": replacement,
        @"nextSelection": [NSValue valueWithRange:nextSelection]
    };
}

- (NSString *)sourceByApplyingEdit:(NSDictionary *)edit toSource:(NSString *)source
{
    NSMutableString *mutable = [source mutableCopy];
    NSRange replaceRange = [[edit objectForKey:@"replaceRange"] rangeValue];
    NSString *replacement = [edit objectForKey:@"replacement"];
    [mutable replaceCharactersInRange:replaceRange withString:replacement];
    NSString *updated = [NSString stringWithString:mutable];
    [mutable release];
    return updated;
}

- (void)testBoldToggleMultilineMixedSelectionNormalizesThenUnwraps
{
    NSString *source = @"alpha\n**beta**\ngamma";
    NSRange selection = NSMakeRange(0, [source length]);

    NSDictionary *first = [self editForSource:source
                                    selection:selection
                                       prefix:@"**"
                                       suffix:@"**"
                                  placeholder:@"bold text"];
    NSString *firstSource = [self sourceByApplyingEdit:first toSource:source];
    XCTAssertEqualObjects(firstSource, @"**alpha**\n**beta**\n**gamma**");

    NSRange firstSelection = [[first objectForKey:@"nextSelection"] rangeValue];
    XCTAssertEqual(firstSelection.location, (NSUInteger)0);
    XCTAssertEqual(firstSelection.length, [firstSource length]);

    NSDictionary *second = [self editForSource:firstSource
                                     selection:firstSelection
                                        prefix:@"**"
                                        suffix:@"**"
                                   placeholder:@"bold text"];
    NSString *secondSource = [self sourceByApplyingEdit:second toSource:firstSource];
    XCTAssertEqualObjects(secondSource, @"alpha\nbeta\ngamma");
}

- (void)testInlineSelectionInsideBoldWrappersIsReversibleAcrossTwoToggles
{
    NSString *source = @"prefix **core** suffix";
    NSRange initialSelection = [source rangeOfString:@"core"];

    NSDictionary *first = [self editForSource:source
                                    selection:initialSelection
                                       prefix:@"**"
                                       suffix:@"**"
                                  placeholder:@"bold text"];
    NSString *firstSource = [self sourceByApplyingEdit:first toSource:source];
    XCTAssertEqualObjects(firstSource, @"prefix core suffix");

    NSRange firstSelection = [[first objectForKey:@"nextSelection"] rangeValue];
    NSDictionary *second = [self editForSource:firstSource
                                     selection:firstSelection
                                        prefix:@"**"
                                        suffix:@"**"
                                   placeholder:@"bold text"];
    NSString *secondSource = [self sourceByApplyingEdit:second toSource:firstSource];
    XCTAssertEqualObjects(secondSource, source);
}

- (void)testItalicToggleMultilineMixedSelectionPreservesLineWhitespace
{
    NSString *source = @"  one\n\t*two*\n  three  ";
    NSRange selection = NSMakeRange(0, [source length]);

    NSDictionary *first = [self editForSource:source
                                    selection:selection
                                       prefix:@"*"
                                       suffix:@"*"
                                  placeholder:@"italic text"];
    NSString *firstSource = [self sourceByApplyingEdit:first toSource:source];
    XCTAssertEqualObjects(firstSource, @"  *one*\n\t*two*\n  *three*  ");

    NSRange firstSelection = [[first objectForKey:@"nextSelection"] rangeValue];
    NSDictionary *second = [self editForSource:firstSource
                                     selection:firstSelection
                                        prefix:@"*"
                                        suffix:@"*"
                                   placeholder:@"italic text"];
    NSString *secondSource = [self sourceByApplyingEdit:second toSource:firstSource];
    XCTAssertEqualObjects(secondSource, @"  one\n\ttwo\n  three  ");
}

- (void)testInlineCodeToggleMultilineMixedSelectionNormalizesThenUnwraps
{
    NSString *source = @"alpha\n`beta`\ngamma";
    NSRange selection = NSMakeRange(0, [source length]);

    NSDictionary *first = [self editForSource:source
                                    selection:selection
                                       prefix:@"`"
                                       suffix:@"`"
                                  placeholder:@"code"];
    NSString *firstSource = [self sourceByApplyingEdit:first toSource:source];
    XCTAssertEqualObjects(firstSource, @"`alpha`\n`beta`\n`gamma`");

    NSRange firstSelection = [[first objectForKey:@"nextSelection"] rangeValue];
    NSDictionary *second = [self editForSource:firstSource
                                     selection:firstSelection
                                        prefix:@"`"
                                        suffix:@"`"
                                   placeholder:@"code"];
    NSString *secondSource = [self sourceByApplyingEdit:second toSource:firstSource];
    XCTAssertEqualObjects(secondSource, @"alpha\nbeta\ngamma");
}

- (void)testBoldToggleSingleWordSelectionIsTwoPressReversible
{
    NSString *source = @"alpha beta gamma";
    NSRange selection = [source rangeOfString:@"beta"];

    NSDictionary *first = [self editForSource:source
                                    selection:selection
                                       prefix:@"**"
                                       suffix:@"**"
                                  placeholder:@"bold text"];
    NSString *firstSource = [self sourceByApplyingEdit:first toSource:source];
    XCTAssertEqualObjects(firstSource, @"alpha **beta** gamma");

    NSRange firstSelection = [[first objectForKey:@"nextSelection"] rangeValue];
    NSDictionary *second = [self editForSource:firstSource
                                     selection:firstSelection
                                        prefix:@"**"
                                        suffix:@"**"
                                   placeholder:@"bold text"];
    NSString *secondSource = [self sourceByApplyingEdit:second toSource:firstSource];
    XCTAssertEqualObjects(secondSource, source);
}

- (void)testItalicToggleSingleWordSelectionIsTwoPressReversible
{
    NSString *source = @"alpha beta gamma";
    NSRange selection = [source rangeOfString:@"beta"];

    NSDictionary *first = [self editForSource:source
                                    selection:selection
                                       prefix:@"*"
                                       suffix:@"*"
                                  placeholder:@"italic text"];
    NSString *firstSource = [self sourceByApplyingEdit:first toSource:source];
    XCTAssertEqualObjects(firstSource, @"alpha *beta* gamma");

    NSRange firstSelection = [[first objectForKey:@"nextSelection"] rangeValue];
    NSDictionary *second = [self editForSource:firstSource
                                     selection:firstSelection
                                        prefix:@"*"
                                        suffix:@"*"
                                   placeholder:@"italic text"];
    NSString *secondSource = [self sourceByApplyingEdit:second toSource:firstSource];
    XCTAssertEqualObjects(secondSource, source);
}

- (void)testInlineCodeToggleSingleWordSelectionIsTwoPressReversible
{
    NSString *source = @"alpha beta gamma";
    NSRange selection = [source rangeOfString:@"beta"];

    NSDictionary *first = [self editForSource:source
                                    selection:selection
                                       prefix:@"`"
                                       suffix:@"`"
                                  placeholder:@"code"];
    NSString *firstSource = [self sourceByApplyingEdit:first toSource:source];
    XCTAssertEqualObjects(firstSource, @"alpha `beta` gamma");

    NSRange firstSelection = [[first objectForKey:@"nextSelection"] rangeValue];
    NSDictionary *second = [self editForSource:firstSource
                                     selection:firstSelection
                                        prefix:@"`"
                                        suffix:@"`"
                                   placeholder:@"code"];
    NSString *secondSource = [self sourceByApplyingEdit:second toSource:firstSource];
    XCTAssertEqualObjects(secondSource, source);
}

@end
