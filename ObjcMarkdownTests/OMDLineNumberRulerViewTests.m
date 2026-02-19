// ObjcMarkdownTests
// SPDX-License-Identifier: Apache-2.0

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDLineNumberRulerView.h"

@interface OMDLineNumberRulerViewTests : XCTestCase
@end

@implementation OMDLineNumberRulerViewTests

- (OMDLineNumberRulerView *)newRulerViewWithTextView:(NSTextView **)textViewOut
                                           scrollView:(NSScrollView **)scrollViewOut
{
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 480, 320)];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasVerticalRuler:YES];
    [scrollView setRulersVisible:YES];

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 480, 320)];
    [textView setEditable:YES];
    [textView setSelectable:YES];
    [textView setRichText:NO];
    [textView setString:@"alpha\nbeta\ngamma\n"];
    [scrollView setDocumentView:textView];

    OMDLineNumberRulerView *ruler = [[OMDLineNumberRulerView alloc] initWithScrollView:scrollView
                                                                                textView:textView];
    [scrollView setVerticalRulerView:ruler];

    if (textViewOut != NULL) {
        *textViewOut = textView;
    } else {
        [textView release];
    }

    if (scrollViewOut != NULL) {
        *scrollViewOut = scrollView;
    } else {
        [scrollView release];
    }

    return ruler;
}

- (void)testGutterMouseEventsDoNotModifyEditorState
{
    NSTextView *textView = nil;
    NSScrollView *scrollView = nil;
    OMDLineNumberRulerView *ruler = [self newRulerViewWithTextView:&textView
                                                         scrollView:&scrollView];
    [textView setSelectedRange:NSMakeRange(2, 3)];
    NSRange selectedBefore = [textView selectedRange];
    NSString *stringBefore = [[textView string] copy];
    CGFloat thicknessBefore = [ruler ruleThickness];

    [ruler mouseDown:nil];
    [ruler mouseDragged:nil];
    [ruler mouseUp:nil];
    [ruler rightMouseDown:nil];
    [ruler otherMouseDown:nil];

    NSRange selectedAfter = [textView selectedRange];
    XCTAssertEqual(selectedAfter.location, selectedBefore.location);
    XCTAssertEqual(selectedAfter.length, selectedBefore.length);
    XCTAssertEqualObjects([textView string], stringBefore);
    XCTAssertEqualWithAccuracy([ruler ruleThickness], thicknessBefore, 0.001);

    [stringBefore release];
    [ruler release];
    [scrollView release];
    [textView release];
}

@end
