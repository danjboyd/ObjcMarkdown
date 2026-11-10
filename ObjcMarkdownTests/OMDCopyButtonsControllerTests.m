// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDCopyButtonsController.h"
#import "OMDTextView.h"
#import "OMMarkdownRenderer.h"
#import "OMDRenderResult.h"

@interface OMDTextView (CopyCodeBlockTesting)
- (BOOL)copyCodeBlockAtIndex:(NSUInteger)blockIndex toPasteboard:(NSPasteboard *)pasteboard;
@end

// Records the copy command without contacting the system pasteboard.
@interface OMDRecordingPasteboard : NSObject
{
    NSArray *_declaredTypes;
    NSString *_copiedString;
}
- (NSArray *)types;
- (NSString *)stringForType:(NSString *)type;
@end

@implementation OMDRecordingPasteboard
- (NSInteger)declareTypes:(NSArray *)types owner:(id)owner
{
    (void)owner;
    [_declaredTypes release];
    _declaredTypes = [types copy];
    return (NSInteger)[_declaredTypes count];
}
- (BOOL)setString:(NSString *)string forType:(NSString *)type
{
    if (_declaredTypes == nil || ![_declaredTypes containsObject:type]) {
        return NO;
    }
    [_copiedString release];
    _copiedString = [string copy];
    return YES;
}
- (NSArray *)types { return _declaredTypes; }
- (NSString *)stringForType:(NSString *)type
{
    return [_declaredTypes containsObject:type] ? _copiedString : nil;
}
- (void)dealloc
{
    [_declaredTypes release];
    [_copiedString release];
    [super dealloc];
}
@end

// The preview a copy-buttons controller works for: a text view, in a
// scroll view or not, and the renderer that drew it.
@interface OMDCopyButtonsTestPreview : NSObject <OMDCopyButtonsControllerDelegate>
{
    OMDTextView *_textView;
    OMMarkdownRenderer *_renderer;
}
- (instancetype)initWithTextView:(OMDTextView *)textView renderer:(OMMarkdownRenderer *)renderer;
@end

@implementation OMDCopyButtonsTestPreview
- (instancetype)initWithTextView:(OMDTextView *)textView renderer:(OMMarkdownRenderer *)renderer
{
    self = [super init];
    if (self != nil) {
        _textView = [textView retain];
        _renderer = [renderer retain];
    }
    return self;
}
- (void)dealloc
{
    [_textView release];
    [_renderer release];
    [super dealloc];
}
- (NSTextView *)previewTextView { return _textView; }
- (OMDRenderResult *)previewRenderResult
{
    return [OMDRenderResult resultOfRenderer:_renderer markdown:nil sourceRevision:0];
}
- (void)previewDidLayoutForCopyButtons { }
@end

@interface OMDCopyButtonsControllerTests : XCTestCase
@end

@implementation OMDCopyButtonsControllerTests

- (void)setUp
{
    [super setUp];
    // GNUstep needs the application (and its backend) before fonts.
    [NSApplication sharedApplication];
}

- (NSString *)markdownWithCodeBlocks:(NSUInteger)count
{
    NSMutableString *markdown = [NSMutableString string];
    NSUInteger index = 1;
    for (; index <= count; index++) {
        [markdown appendFormat:@"## Section %lu\n\nA paragraph between the blocks.\n\n```objc\nNSLog(@\"block %lu\");\n```\n\n",
                               (unsigned long)index, (unsigned long)index];
    }
    return markdown;
}

- (OMDTextView *)textViewForMarkdown:(NSString *)markdown renderer:(OMMarkdownRenderer *)renderer
{
    [renderer setLayoutWidth:600.0];
    OMDTextView *textView = [[[OMDTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 600.0)] autorelease];
    [textView setEditable:NO];
    [textView setRichText:YES];
    [textView setVerticallyResizable:YES];
    [textView setMaxSize:NSMakeSize(640.0, 1.0e7)];
    [[textView textContainer] setContainerSize:NSMakeSize(600.0, 1.0e7)];
    [[textView textContainer] setWidthTracksTextView:NO];
    [[textView textStorage] setAttributedString:[renderer attributedStringFromMarkdown:markdown]];
    [textView setCodeBlockRanges:[renderer codeBlockRanges]];
    [[textView layoutManager] ensureLayoutForTextContainer:[textView textContainer]];
    [textView sizeToFit];
    return textView;
}

- (NSArray *)buttonsInView:(NSView *)view
{
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSView *subview in [view subviews]) {
        if ([subview isKindOfClass:[NSButton class]]) {
            [buttons addObject:subview];
        }
    }
    return buttons;
}

- (NSDictionary *)framesByTagOfButtons:(NSArray *)buttons
{
    NSMutableDictionary *frames = [NSMutableDictionary dictionary];
    for (NSButton *button in buttons) {
        [frames setObject:[NSValue valueWithRect:[button frame]] forKey:[NSNumber numberWithInteger:[button tag]]];
    }
    return frames;
}

// Only the blocks near what's visible get a button (#346), each where it
// went when every block had one, and scrolling brings the others in.
- (void)testButtonsOnlyNearTheVisibleRectAndWhereTheyWere
{
    NSString *markdown = [self markdownWithCodeBlocks:200];

    // Every block's button, as before: a text view in no scroll view.
    OMMarkdownRenderer *allRenderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    OMDTextView *allView = [self textViewForMarkdown:markdown renderer:allRenderer];
    OMDCopyButtonsTestPreview *allPreview = [[[OMDCopyButtonsTestPreview alloc] initWithTextView:allView renderer:allRenderer] autorelease];
    OMDCopyButtonsController *allController = [[[OMDCopyButtonsController alloc] initWithDelegate:allPreview] autorelease];
    [allController updateCodeBlockButtons];
    NSDictionary *expected = [self framesByTagOfButtons:[self buttonsInView:allView]];
    XCTAssertEqual([expected count], (NSUInteger)200);

    // The same document in a 600 pt scroll view.
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    OMDTextView *textView = [self textViewForMarkdown:markdown renderer:renderer];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 600.0)
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 600.0)] autorelease];
    [scrollView setDocumentView:textView];
    [[window contentView] addSubview:scrollView];
    OMDCopyButtonsTestPreview *preview = [[[OMDCopyButtonsTestPreview alloc] initWithTextView:textView renderer:renderer] autorelease];
    OMDCopyButtonsController *controller = [[OMDCopyButtonsController alloc] initWithDelegate:preview];
    [controller updateCodeBlockButtons];

    CGFloat positions[] = { 0.0, 0.5, 1.0 };
    NSUInteger p = 0;
    for (; p < 3; p++) {
        CGFloat maxY = NSHeight([textView frame]) - NSHeight([[scrollView contentView] bounds]);
        [[scrollView contentView] scrollToPoint:NSMakePoint(0.0, floor(maxY * positions[p]))];
        [scrollView reflectScrolledClipView:[scrollView contentView]];
        // The bounds-changed notification has updated the buttons.
        NSArray *buttons = [self buttonsInView:textView];
        NSRect visible = [textView visibleRect];
        XCTAssertTrue([buttons count] > 0 && [buttons count] < 40, @"%lu buttons at %.1f", (unsigned long)[buttons count], positions[p]);

        // A screen above and below, and the block whose text touches that
        // area's edge: within two screens.
        NSRect nearby = NSInsetRect(visible, 0.0, -2.0 * NSHeight(visible));
        BOOL coversVisible = NO;
        for (NSButton *button in buttons) {
            NSNumber *tag = [NSNumber numberWithInteger:[button tag]];
            XCTAssertTrue(NSEqualRects([button frame], [[expected objectForKey:tag] rectValue]),
                          @"button %@ at %@, was at %@", tag, NSStringFromRect([button frame]),
                          NSStringFromRect([[expected objectForKey:tag] rectValue]));
            XCTAssertTrue(NSIntersectsRect([button frame], nearby), @"button %@ far from the visible rect", tag);
            XCTAssertEqualObjects([button toolTip], @"Copy code block");
#if !defined(GNUSTEP)
            XCTAssertEqualObjects([button accessibilityLabel], @"Copy code block");
#endif
            if (NSIntersectsRect([button frame], visible)) {
                coversVisible = YES;
            }
        }
        // Every block whose button falls in the visible rect has one.
        for (NSNumber *tag in expected) {
            NSRect frame = [[expected objectForKey:tag] rectValue];
            if (NSIntersectsRect(frame, visible)) {
                NSUInteger found = [[buttons valueForKey:@"tag"] indexOfObject:tag];
                XCTAssertTrue(found != NSNotFound, @"no button for visible block %@", tag);
            }
        }
        XCTAssertTrue(coversVisible, @"no button in the visible rect at %.1f", positions[p]);
    }

    [controller removeCopyButtons];
    XCTAssertEqual([[self buttonsInView:textView] count], (NSUInteger)0);
    [controller release];
    [scrollView removeFromSuperview];
    [window release];
}

// Keyboard and VoiceOver users reach the copy action without the button:
// Edit > Copy Code Block copies the block holding the selection.
- (void)testCopyCodeBlockAtSelection
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    OMDTextView *textView = [self textViewForMarkdown:[self markdownWithCodeBlocks:3] renderer:renderer];
    NSString *text = [[textView textStorage] string];
    NSRange second = [text rangeOfString:@"block 2"];
    XCTAssertTrue(second.location != NSNotFound);

    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"Copy Code Block"
                                                   action:@selector(copyCodeBlockAtSelection:)
                                            keyEquivalent:@""] autorelease];
    [textView setSelectedRange:NSMakeRange(second.location, 0)];
    XCTAssertEqual([textView codeBlockIndexAtCharacterIndex:second.location], (NSUInteger)1);
    XCTAssertTrue([textView validateMenuItem:item]);

    OMDRecordingPasteboard *pasteboard = [[[OMDRecordingPasteboard alloc] init] autorelease];
    XCTAssertTrue([textView copyCodeBlockAtIndex:[textView codeBlockIndexAtCharacterIndex:second.location]
                                    toPasteboard:(NSPasteboard *)pasteboard]);
    XCTAssertEqualObjects([pasteboard types], [NSArray arrayWithObject:NSStringPboardType]);
    NSString *copied = [pasteboard stringForType:NSStringPboardType];
    XCTAssertTrue([copied rangeOfString:@"NSLog(@\"block 2\");"].location != NSNotFound, @"%@", copied);
    XCTAssertTrue([copied rangeOfString:@"block 1"].location == NSNotFound, @"%@", copied);

    NSRange paragraph = [text rangeOfString:@"A paragraph between"];
    [textView setSelectedRange:NSMakeRange(paragraph.location, 0)];
    XCTAssertEqual([textView codeBlockIndexAtCharacterIndex:paragraph.location], (NSUInteger)NSNotFound);
    XCTAssertFalse([textView validateMenuItem:item]);
}

// Run separately when the clipboard service is free. The recording test above
// covers the copy path during ordinary suite runs without contacting pasteboardd.
- (void)testCopyCodeBlockWritesToRealPasteboardWhenRequested
{
    XCTSkipUnless([[[[NSProcessInfo processInfo] environment] objectForKey:@"OMD_TEST_REAL_PASTEBOARD"] isEqualToString:@"1"],
                  @"Set OMD_TEST_REAL_PASTEBOARD=1 for the separate clipboard integration check");

    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    OMDTextView *textView = [self textViewForMarkdown:[self markdownWithCodeBlocks:3] renderer:renderer];
    NSString *text = [[textView textStorage] string];
    NSUInteger index = [text rangeOfString:@"block 2"].location;
    XCTAssertNotEqual(index, (NSUInteger)NSNotFound);
    if (index == NSNotFound) {
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    @try {
        XCTAssertTrue([textView copyCodeBlockAtIndex:[textView codeBlockIndexAtCharacterIndex:index]
                                        toPasteboard:pasteboard]);
        XCTAssertEqualObjects([pasteboard types], [NSArray arrayWithObject:NSStringPboardType]);
        NSString *copied = [pasteboard stringForType:NSStringPboardType];
        XCTAssertTrue([copied rangeOfString:@"NSLog(@\"block 2\");"].location != NSNotFound, @"%@", copied);
        XCTAssertTrue([copied rangeOfString:@"block 1"].location == NSNotFound, @"%@", copied);
    } @finally {
        [pasteboard releaseGlobally];
    }
}

// A right click in a code block offers Copy Code Block.
- (void)testTextMenuInACodeBlockOffersCopyCodeBlock
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    OMDTextView *textView = [self textViewForMarkdown:[self markdownWithCodeBlocks:3] renderer:renderer];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 800.0)
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [[window contentView] addSubview:textView];
    NSString *text = [[textView textStorage] string];

    NSUInteger inBlock = [text rangeOfString:@"block 3"].location + 2;
    NSUInteger inParagraph = [text rangeOfString:@"A paragraph between"].location + 2;
    NSUInteger indexes[] = { inBlock, inParagraph };
    NSUInteger i = 0;
    for (; i < 2; i++) {
        NSLayoutManager *layoutManager = [textView layoutManager];
        NSRange glyph = [layoutManager glyphRangeForCharacterRange:NSMakeRange(indexes[i], 1) actualCharacterRange:NULL];
        NSRect rect = [layoutManager boundingRectForGlyphRange:glyph inTextContainer:[textView textContainer]];
        NSPoint origin = [textView textContainerOrigin];
        NSPoint centre = NSMakePoint(NSMidX(rect) + origin.x, NSMidY(rect) + origin.y);
        NSEvent *click = [NSEvent mouseEventWithType:NSRightMouseDown
                                            location:[textView convertPoint:centre toView:nil]
                                       modifierFlags:0
                                           timestamp:0.0
                                        windowNumber:[window windowNumber]
                                             context:nil
                                         eventNumber:0
                                          clickCount:1
                                            pressure:1.0];
        NSMenu *menu = [textView menuForEvent:click];
        NSMenuItem *item = (NSMenuItem *)[menu itemWithTitle:@"Copy Code Block"];
        if (i == 0) {
            XCTAssertNotNil(item, @"no Copy Code Block in %@", [menu itemArray]);
            XCTAssertEqual([item tag], (NSInteger)2);
        } else {
            XCTAssertNil(item);
        }
    }
    [textView removeFromSuperview];
    [window release];
}

@end
