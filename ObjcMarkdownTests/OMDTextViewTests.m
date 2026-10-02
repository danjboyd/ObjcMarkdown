// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDTextView.h"
#import "OMStrikethroughLayoutManager.h"
#import "OMMarkdownRenderer.h"
#import "OMRenderedObject.h"

// The tool tip owner callback OMDTextView implements for its object rects.
@interface OMDTextView (ToolTipOwner)
- (NSString *)view:(NSView *)view
  stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point
          userData:(void *)userData;
@end

@interface OMDTextViewTests : XCTestCase
@end

@implementation OMDTextViewTests

- (OMDTextView *)textViewShowingMarkdown:(NSString *)markdown
{
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] init] autorelease];
    [renderer setLayoutWidth:600.0];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    OMDTextView *textView = [[[OMDTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 800.0)] autorelease];
    [textView setEditable:NO];
    [textView setSelectable:YES];
    [textView setRichText:YES];
    [[textView textStorage] setAttributedString:rendered];
    [[textView layoutManager] glyphRangeForTextContainer:[textView textContainer]];
    return textView;
}

- (NSUInteger)firstObjectIndexInTextView:(OMDTextView *)textView
{
    NSTextStorage *storage = [textView textStorage];
    NSUInteger index = 0;
    for (; index < [storage length]; index++) {
        if ([storage attribute:OMRenderedObjectAttributeName atIndex:index effectiveRange:NULL] != nil) {
            return index;
        }
    }
    return NSNotFound;
}

- (NSString *)tableMarkdown
{
    return @"| a | b |\n|---|---|\n| 1 | 2 |";
}

- (void)testCopyingMixedSelectionWritesObjectsAsMarkdown
{
    NSString *markdown = [NSString stringWithFormat:@"Before\n\n%@\n\nAfter", [self tableMarkdown]];
    OMDTextView *textView = [self textViewShowingMarkdown:markdown];
    [textView setSelectedRange:NSMakeRange(0, [[textView textStorage] length])];

    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    NSArray *types = [NSArray arrayWithObjects:NSStringPboardType, NSRTFPboardType, nil];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard types:types]);
    NSString *text = [pboard stringForType:NSStringPboardType];
    XCTAssertTrue([text rangeOfString:[self tableMarkdown]].location != NSNotFound);
    XCTAssertTrue([text hasPrefix:@"Before"]);
    XCTAssertTrue([text hasSuffix:@"After"]);
    unichar attachmentCharacter = NSAttachmentCharacter;
    XCTAssertTrue([text rangeOfString:[NSString stringWithCharacters:&attachmentCharacter length:1]].location == NSNotFound);

    NSData *rtf = [pboard dataForType:NSRTFPboardType];
    XCTAssertNotNil(rtf);
    NSAttributedString *fromRTF = [[[NSAttributedString alloc] initWithRTF:rtf documentAttributes:NULL] autorelease];
    XCTAssertTrue([[fromRTF string] rangeOfString:@"|---|---|"].location != NSNotFound);
    [pboard releaseGlobally];
}

- (void)testCopyingOneObjectWritesItsSourceAndAnImage
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self tableMarkdown]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    if (index == NSNotFound) {
        return;
    }
    [textView setSelectedRange:NSMakeRange(index, 1)];

    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard
                                                 types:[NSArray arrayWithObject:NSStringPboardType]]);
    XCTAssertEqualObjects([pboard stringForType:NSStringPboardType], [self tableMarkdown]);
    NSData *tiff = [pboard dataForType:NSTIFFPboardType];
    XCTAssertNotNil(tiff);
    NSImage *image = [[[NSImage alloc] initWithData:tiff] autorelease];
    XCTAssertTrue([image size].width > 0.0 && [image size].height > 0.0);
    [pboard releaseGlobally];
}

- (void)testPlainTextSelectionCopiesNormally
{
    OMDTextView *textView = [self textViewShowingMarkdown:@"Just *some* text."];
    [textView setSelectedRange:NSMakeRange(0, 4)];
    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    XCTAssertTrue([textView writeSelectionToPasteboard:pboard
                                                 types:[NSArray arrayWithObject:NSStringPboardType]]);
    XCTAssertEqualObjects([pboard stringForType:NSStringPboardType], @"Just");
    XCTAssertNil([pboard dataForType:NSTIFFPboardType]);
    [pboard releaseGlobally];
}

- (void)testEscapeClearsSelectionInReadOnlyPreview
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self tableMarkdown]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    [textView setSelectedRange:NSMakeRange(index, 1)];
    NSEvent *escape = [NSEvent keyEventWithType:NSKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0.0
                                   windowNumber:0
                                        context:nil
                                     characters:@"\x1b"
                    charactersIgnoringModifiers:@"\x1b"
                                      isARepeat:NO
                                        keyCode:9];
    [textView keyDown:escape];
    XCTAssertEqual([textView selectedRange].length, (NSUInteger)0);
    XCTAssertEqual([textView selectedRange].location, index);
}

- (void)testToolTipShowsObjectSource
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self tableMarkdown]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    XCTAssertFalse(NSIsEmptyRect([textView viewRectForRenderedObjectAtIndex:index]));
    [textView updateRenderedObjectToolTips];
    NSString *tip = [textView view:textView
                      stringForToolTip:0
                                 point:NSZeroPoint
                              userData:(void *)(uintptr_t)index];
    XCTAssertEqualObjects(tip, [self tableMarkdown]);
}

- (void)testSourceLocationFindsItsObject
{
    NSString *markdown = [NSString stringWithFormat:@"Intro\n\n%@\n\nOutro", [self tableMarkdown]];
    OMDTextView *textView = [self textViewShowingMarkdown:markdown];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    NSUInteger insideTable = [markdown rangeOfString:@"| 1 |"].location;
    XCTAssertEqual([textView renderedObjectIndexContainingSourceLocation:insideTable], index);
    XCTAssertEqual([textView renderedObjectIndexContainingSourceLocation:2], (NSUInteger)NSNotFound);
    XCTAssertEqual([textView renderedObjectIndexContainingSourceLocation:[markdown length] - 2], (NSUInteger)NSNotFound);
}

- (void)testLinkedObjectIndexDefaultsToNotFound
{
    OMDTextView *textView = [self textViewShowingMarkdown:[self tableMarkdown]];
    XCTAssertEqual([textView linkedObjectIndex], (NSUInteger)NSNotFound);
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    [textView setLinkedObjectIndex:index];
    XCTAssertEqual([textView linkedObjectIndex], index);
    [textView setLinkedObjectIndex:NSNotFound];
    XCTAssertEqual([textView linkedObjectIndex], (NSUInteger)NSNotFound);
}

// A text view showing text, with strikethrough over the given ranges.
- (OMDTextView *)textViewWithText:(NSString *)text struckRanges:(NSArray *)ranges width:(CGFloat)width
{
    OMDTextView *textView = [[[OMDTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 400.0)] autorelease];
    NSFont *font = [NSFont userFontOfSize:14.0];
    NSMutableAttributedString *string = [[[NSMutableAttributedString alloc]
        initWithString:text attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]] autorelease];
    for (NSValue *range in ranges) {
        [string addAttribute:NSStrikethroughStyleAttributeName
                       value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
                       range:[range rangeValue]];
    }
    [[textView textStorage] setAttributedString:string];
    [[textView layoutManager] glyphRangeForTextContainer:[textView textContainer]];
    return textView;
}

- (void)testStrikethroughLineCrossesStruckWordOnly
{
    NSString *text = @"plain struck plain";
    NSRange struck = [text rangeOfString:@"struck"];
    OMDTextView *textView = [self textViewWithText:text struckRanges:[NSArray arrayWithObject:[NSValue valueWithRange:struck]] width:600.0];
    OMStrikethroughLayoutManager *layoutManager = (OMStrikethroughLayoutManager *)[textView layoutManager];
    XCTAssertTrue([layoutManager isKindOfClass:[OMStrikethroughLayoutManager class]]);

    NSRange allGlyphs = NSMakeRange(0, [layoutManager numberOfGlyphs]);
    NSArray *rects = [layoutManager strikethroughLineRectsForGlyphRange:allGlyphs atPoint:NSZeroPoint];
    XCTAssertEqual([rects count], (NSUInteger)1);
    if ([rects count] != 1) {
        return;
    }
    NSRect line = [[rects objectAtIndex:0] rectValue];
    NSRange struckGlyphs = [layoutManager glyphRangeForCharacterRange:struck actualCharacterRange:NULL];
    NSRect word = [layoutManager boundingRectForGlyphRange:struckGlyphs inTextContainer:[textView textContainer]];
    XCTAssertEqualWithAccuracy(NSMinX(line), NSMinX(word), 0.5);
    XCTAssertEqualWithAccuracy(NSWidth(line), NSWidth(word), 0.5);
    CGFloat baseline = NSMinY([layoutManager lineFragmentRectForGlyphAtIndex:struckGlyphs.location effectiveRange:NULL]) +
                       [layoutManager locationForGlyphAtIndex:struckGlyphs.location].y;
    XCTAssertTrue(NSMaxY(line) < baseline, @"line should sit above the baseline");
    XCTAssertTrue(NSMinY(line) > baseline - [[NSFont userFontOfSize:14.0] xHeight] - 1.0, @"line should sit within the x-height");
    XCTAssertTrue(NSHeight(line) >= 1.0);
}

- (void)testStrikethroughGetsOneLinePerWrappedLine
{
    NSString *text = @"alpha beta gamma delta epsilon zeta eta theta iota kappa";
    OMDTextView *textView = [self textViewWithText:text
                                      struckRanges:[NSArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(0, [text length])]]
                                             width:120.0];
    OMStrikethroughLayoutManager *layoutManager = (OMStrikethroughLayoutManager *)[textView layoutManager];
    NSRange allGlyphs = NSMakeRange(0, [layoutManager numberOfGlyphs]);
    NSUInteger lineCount = 0;
    NSUInteger glyph = 0;
    while (glyph < NSMaxRange(allGlyphs)) {
        NSRange fragment;
        [layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&fragment];
        lineCount += 1;
        glyph = NSMaxRange(fragment);
    }
    XCTAssertTrue(lineCount > 1);
    NSArray *rects = [layoutManager strikethroughLineRectsForGlyphRange:allGlyphs atPoint:NSZeroPoint];
    XCTAssertEqual([rects count], lineCount);
}

- (void)testUnstruckTextHasNoStrikethroughLines
{
    OMDTextView *textView = [self textViewWithText:@"nothing struck here\n" struckRanges:[NSArray array] width:600.0];
    OMStrikethroughLayoutManager *layoutManager = (OMStrikethroughLayoutManager *)[textView layoutManager];
    NSArray *rects = [layoutManager strikethroughLineRectsForGlyphRange:NSMakeRange(0, [layoutManager numberOfGlyphs])
                                                                atPoint:NSZeroPoint];
    XCTAssertEqual([rects count], (NSUInteger)0);
}

- (void)testStrikethroughHelperDrawsAtMidXHeightInUnflippedContext
{
    NSFont *font = [NSFont userFontOfSize:20.0];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName,
                                [NSNumber numberWithInteger:NSUnderlineStyleSingle], NSStrikethroughStyleAttributeName,
                                [NSColor blackColor], NSForegroundColorAttributeName, nil];
    NSAttributedString *string = [[[NSAttributedString alloc] initWithString:@"struck" attributes:attributes] autorelease];
    NSSize size = NSMakeSize(200.0, 60.0);
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));
    // Only the line, no glyphs, so every dark pixel belongs to it.
    OMDrawStrikethroughForAttributedString(string, NSMakeRect(0.0, 0.0, size.width, size.height), NO);
    [image unlockFocus];

    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    XCTAssertNotNil(bitmap);
    NSInteger top = NSIntegerMax;
    NSInteger bottom = -1;
    NSInteger x = 0;
    for (; x < [bitmap pixelsWide]; x++) {
        NSInteger y = 0;
        for (; y < [bitmap pixelsHigh]; y++) {
            NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if ([color redComponent] < 0.5) {
                top = MIN(top, y);
                bottom = MAX(bottom, y);
            }
        }
    }
    XCTAssertTrue(bottom >= 0, @"the strikethrough line should be drawn");
    // Bitmap rows count from the top; the text sits at the top of an unflipped rect.
    CGFloat ascent = [font ascender];
    CGFloat expectedMiddle = ascent - [font xHeight] * 0.5;
    XCTAssertTrue(bottom - top <= 3, @"a thin line, not a block");
    XCTAssertEqualWithAccuracy((top + bottom) * 0.5, expectedMiddle, 4.0);
}

- (void)testLinkTitleIsOfferedAsToolTip
{
    OMDTextView *textView = [self textViewShowingMarkdown:@"See [docs](https://example.com \"The docs\") now."];
    NSUInteger link = [[[textView textStorage] string] rangeOfString:@"docs"].location;
    [textView updateRenderedObjectToolTips];
    NSString *tip = [textView view:textView stringForToolTip:0 point:NSZeroPoint userData:(void *)(uintptr_t)link];
    XCTAssertEqualObjects(tip, @"The docs");
}

- (void)testHitTestingFindsObjectOnlyInsideItsBox
{
    OMDTextView *textView = [self textViewShowingMarkdown:[NSString stringWithFormat:@"Intro\n\n%@", [self tableMarkdown]]];
    NSUInteger index = [self firstObjectIndexInTextView:textView];
    XCTAssertTrue(index != NSNotFound);
    if (index == NSNotFound) {
        return;
    }
    NSLayoutManager *layoutManager = [textView layoutManager];
    NSRange glyphs = [layoutManager glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL];
    NSRect box = [layoutManager boundingRectForGlyphRange:glyphs inTextContainer:[textView textContainer]];
    NSPoint origin = [textView textContainerOrigin];
    NSPoint inside = NSMakePoint(NSMidX(box) + origin.x, NSMidY(box) + origin.y);

    NSUInteger hitIndex = NSNotFound;
    OMRenderedObject *object = [textView renderedObjectAtPoint:inside characterIndex:&hitIndex];
    XCTAssertNotNil(object);
    XCTAssertEqual(hitIndex, index);
    XCTAssertEqual([object kind], OMRenderedObjectKindTable);

    NSPoint outside = NSMakePoint(NSMaxX(box) + origin.x + 40.0, NSMidY(box) + origin.y);
    XCTAssertNil([textView renderedObjectAtPoint:outside characterIndex:NULL]);
    NSPoint onIntro = NSMakePoint(origin.x + 4.0, origin.y + 4.0);
    XCTAssertNil([textView renderedObjectAtPoint:onIntro characterIndex:NULL]);
}

@end
