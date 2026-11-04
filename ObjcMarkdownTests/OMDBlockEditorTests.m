// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

// Edit Block (#294) spike: paragraphs only. The invariants from
// docs/read-edit-design.md: every edit in an open block changes the source
// only inside the block's range; opening and closing without typing leaves
// the source byte-identical; the preview takes edits only inside the block.

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMMarkdownRenderer.h"
#import "OMMarkdownParsingOptions.h"
#import "OMDBlockEditor.h"
#import "OMDTextView.h"

#ifndef OM_SPEC_DIR
#define OM_SPEC_DIR "Spec"
#endif

// The source as a plain string, as the tests' model of the source editor.
@interface OMDTestBlockSource : NSObject <OMDBlockEditorSource>
{
@public
    NSMutableString *_text;
    NSUInteger _replacements;
}
@end

@implementation OMDTestBlockSource

- (instancetype)initWithString:(NSString *)string
{
    self = [super init];
    if (self != nil) {
        _text = [string mutableCopy];
    }
    return self;
}

- (void)dealloc
{
    [_text release];
    [super dealloc];
}

- (NSString *)blockEditorSourceString
{
    return _text;
}

- (BOOL)blockEditor:(OMDBlockEditor *)editor
    replaceSourceCharactersInRange:(NSRange)range
                        withString:(NSString *)string
{
    (void)editor;
    if (NSMaxRange(range) > [_text length]) {
        return NO;
    }
    [_text replaceCharactersInRange:range withString:string];
    _replacements += 1;
    return YES;
}

@end

// -hasPrefix: and -hasSuffix: are NO for an empty string on macOS.
static BOOL OMDTestStartsWith(NSString *string, NSString *prefix)
{
    return [string length] >= [prefix length] &&
           [[string substringToIndex:[prefix length]] isEqualToString:prefix];
}

static BOOL OMDTestEndsWith(NSString *string, NSString *suffix)
{
    return [string length] >= [suffix length] &&
           [[string substringFromIndex:[string length] - [suffix length]] isEqualToString:suffix];
}

// A small deterministic generator, so a failure repeats.
static uint32_t OMDTestNextRandom(uint32_t *state)
{
    *state = *state * 1664525u + 1013904223u;
    return *state >> 8;
}

// The markdown of each example in a CommonMark spec file ("->" stands for a tab).
static NSArray *OMDTestSpecMarkdown(NSString *path)
{
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray *examples = [NSMutableArray array];
    if (text == nil) {
        return examples;
    }
    NSString *fence = @"```````````````````````````````` example";
    NSMutableString *current = nil;
    BOOL inMarkdown = NO;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:fence]) {
            current = [NSMutableString string];
            inMarkdown = YES;
            continue;
        }
        if (inMarkdown) {
            if ([line isEqualToString:@"."]) {
                [examples addObject:[current stringByReplacingOccurrencesOfString:@"→" withString:@"\t"]];
                inMarkdown = NO;
                current = nil;
            } else {
                [current appendString:line];
                [current appendString:@"\n"];
            }
        }
    }
    return examples;
}

@interface OMDBlockEditorTests : XCTestCase
@end

@implementation OMDBlockEditorTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (OMMarkdownRenderer *)renderer
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyDisabled];
    [options setAllowRemoteImages:NO];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil parsingOptions:options] autorelease];
    [renderer setLayoutWidth:600.0];
    return renderer;
}

- (NSString *)corpusDocument
{
    return @"# Title\n"
            "\n"
            "A plain paragraph with *emphasis*, `code`, a [link](http://example.com \"t\") and &amp; an entity.\n"
            "It wraps onto a second source line.\n"
            "\n"
            "Unicode: café, 日本語, an emoji \U0001F600 and a combining é.\n"
            "\n"
            "- A list item paragraph\n"
            "- [ ] A task item\n"
            "\n"
            "> A quoted paragraph\n"
            "> on two lines.\n"
            "\n"
            "```\n"
            "code is not a paragraph\n"
            "```\n"
            "\n"
            "Hard break here  \n"
            "and after it.\n"
            "\n"
            "Last paragraph, no newline at the end";
}

// Each paragraph is listed once, with its exact source range, and its
// rendered text carries the attribute.
- (void)testParagraphsAreListedWithTheirSourceRanges
{
    NSString *markdown = [self corpusDocument];
    OMMarkdownRenderer *renderer = [self renderer];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSArray *blocks = [renderer editableBlocks];

    NSMutableArray *sources = [NSMutableArray array];
    for (NSDictionary *block in blocks) {
        XCTAssertEqualObjects([block objectForKey:OMMarkdownRendererEditableBlockKindKey], @"paragraph");
        NSRange range = [[block objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];
        [sources addObject:[markdown substringWithRange:range]];
    }
    NSArray *expected = [NSArray arrayWithObjects:
        @"A plain paragraph with *emphasis*, `code`, a [link](http://example.com \"t\") and &amp; an entity.\nIt wraps onto a second source line.",
        @"Unicode: café, 日本語, an emoji \U0001F600 and a combining é.",
        @"A list item paragraph",
        @"A task item",
        @"A quoted paragraph\n> on two lines.",
        @"Hard break here  \nand after it.",
        @"Last paragraph, no newline at the end",
        nil];
    XCTAssertEqualObjects(sources, expected);

    // The n-th attribute run is the n-th block, and it holds the rendered text.
    NSRange renderedRange = NSMakeRange(NSNotFound, 0);
    NSUInteger at = [[rendered string] rangeOfString:@"Unicode:"].location;
    XCTAssertEqual(OMDEditableBlockIndexAtCharacterIndex(rendered, at, &renderedRange), (NSUInteger)1);
    XCTAssertTrue([[[rendered string] substringWithRange:renderedRange] hasPrefix:@"Unicode:"]);
    XCTAssertTrue([[[rendered string] substringWithRange:renderedRange] hasSuffix:@"é."]);
    // A caret just after the block's last character still finds it.
    XCTAssertEqual(OMDEditableBlockIndexAtCharacterIndex(rendered, NSMaxRange(renderedRange), NULL), (NSUInteger)1);
    // Headings and code aren't editable yet.
    at = [[rendered string] rangeOfString:@"code is not"].location;
    XCTAssertEqual(OMDEditableBlockIndexAtCharacterIndex(rendered, at, NULL), (NSUInteger)NSNotFound);
    at = [[rendered string] rangeOfString:@"Title"].location;
    XCTAssertEqual(OMDEditableBlockIndexAtCharacterIndex(rendered, at, NULL), (NSUInteger)NSNotFound);
}

- (void)testSourceRangesFollowCRLFLineEndings
{
    NSString *markdown = @"First\r\nparagraph.\r\n\r\nSecond.\r\n";
    OMMarkdownRenderer *renderer = [self renderer];
    [renderer attributedStringFromMarkdown:markdown];
    NSArray *blocks = [renderer editableBlocks];
    XCTAssertEqual([blocks count], (NSUInteger)2);
    if ([blocks count] == 2) {
        NSRange first = [[[blocks objectAtIndex:0] objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];
        NSRange second = [[[blocks objectAtIndex:1] objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];
        XCTAssertEqualObjects([markdown substringWithRange:first], @"First\r\nparagraph.");
        XCTAssertEqualObjects([markdown substringWithRange:second], @"Second.");
    }
}

// Opens every block of markdown in turn, makes `edits` random edits inside
// it through the preview's text storage, and checks after each one that the
// source changed only inside the block and that the block's source is the
// open text. Then the same block opened and closed with no edit leaves the
// source as it was. Returns the number of blocks checked.
- (NSUInteger)checkMinimalEditsInMarkdown:(NSString *)markdown edits:(NSUInteger)edits seed:(uint32_t)seed
{
    OMMarkdownRenderer *renderer = [self renderer];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSArray *blocks = [renderer editableBlocks];
    NSUInteger checked = 0;
    NSArray *insertions = [NSArray arrayWithObjects:@"x", @" ", @"é", @"\U0001F600", @"*", @"\n", @"[a](b)", @"&amp;", nil];

    for (NSUInteger blockIndex = 0; blockIndex < [blocks count]; blockIndex++) {
        NSRange sourceRange = [[[blocks objectAtIndex:blockIndex] objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];
        // The blockIndex-th run of the attribute.
        NSRange renderedRange = NSMakeRange(NSNotFound, 0);
        NSUInteger found = NSNotFound;
        NSUInteger runs = 0;
        NSUInteger index = 0;
        while (index < [rendered length]) {
            NSRange run = NSMakeRange(index, 1);
            id value = [rendered attribute:OMMarkdownRendererEditableBlockAttributeName atIndex:index
                     longestEffectiveRange:&run inRange:NSMakeRange(0, [rendered length])];
            if (value != nil) {
                if (runs == blockIndex) {
                    found = blockIndex;
                    renderedRange = run;
                    break;
                }
                runs += 1;
            }
            index = NSMaxRange(run) > index ? NSMaxRange(run) : index + 1;
        }
        XCTAssertEqual(found, blockIndex, @"block %lu has no rendered text", (unsigned long)blockIndex);
        if (found == NSNotFound) {
            continue;
        }

        // Round trip with no edit.
        {
            NSTextStorage *preview = [[[NSTextStorage alloc] initWithAttributedString:rendered] autorelease];
            OMDTestBlockSource *source = [[[OMDTestBlockSource alloc] initWithString:markdown] autorelease];
            OMDBlockEditor *editor = [[[OMDBlockEditor alloc] initWithPreviewStorage:preview source:source] autorelease];
            XCTAssertTrue([editor openBlockAtRenderedRange:renderedRange sourceRange:sourceRange attributes:nil]);
            XCTAssertEqualObjects([[preview string] substringWithRange:[editor openRange]],
                                  [markdown substringWithRange:sourceRange]);
            NSRange closed = [editor closeBlock];
            XCTAssertTrue(NSEqualRanges(closed, sourceRange));
            XCTAssertEqualObjects(source->_text, markdown);
            XCTAssertEqual(source->_replacements, (NSUInteger)0);
        }

        NSTextStorage *preview = [[[NSTextStorage alloc] initWithAttributedString:rendered] autorelease];
        OMDTestBlockSource *source = [[[OMDTestBlockSource alloc] initWithString:markdown] autorelease];
        OMDBlockEditor *editor = [[[OMDBlockEditor alloc] initWithPreviewStorage:preview source:source] autorelease];
        XCTAssertTrue([editor openBlockAtRenderedRange:renderedRange sourceRange:sourceRange attributes:nil]);
        NSString *before = [markdown substringToIndex:sourceRange.location];
        NSString *after = [markdown substringFromIndex:NSMaxRange(sourceRange)];
        uint32_t state = seed + (uint32_t)blockIndex * 7919u;

        for (NSUInteger edit = 0; edit < edits; edit++) {
            NSRange open = [editor openRange];
            NSUInteger kind = OMDTestNextRandom(&state) % 3;
            NSUInteger position = open.location + (open.length > 0 ? OMDTestNextRandom(&state) % (open.length + 1) : 0);
            NSRange change = NSMakeRange(position, 0);
            NSString *replacement = @"";
            if (kind != 1) {
                replacement = [insertions objectAtIndex:OMDTestNextRandom(&state) % [insertions count]];
            }
            if (kind != 0) {
                NSUInteger available = NSMaxRange(open) - position;
                change.length = available > 0 ? OMDTestNextRandom(&state) % (available < 4 ? available + 1 : 4) : 0;
            }
            XCTAssertTrue([editor allowsChangeInRange:change]);
            [preview beginEditing];
            [preview replaceCharactersInRange:change withString:replacement];
            [preview endEditing];

            XCTAssertFalse([editor isOutOfSync]);
            NSString *now = source->_text;
            NSRange blockSource = [editor sourceRange];
            BOOL keptBefore = OMDTestStartsWith(now, before);
            BOOL keptAfter = OMDTestEndsWith(now, after);
            XCTAssertTrue(keptBefore, @"source before block %lu changed", (unsigned long)blockIndex);
            XCTAssertTrue(keptAfter, @"source after block %lu changed", (unsigned long)blockIndex);
            XCTAssertEqual([now length], [before length] + blockSource.length + [after length]);
            XCTAssertEqualObjects([now substringWithRange:blockSource],
                                  [[preview string] substringWithRange:[editor openRange]]);
            if ([editor isOutOfSync] || !keptBefore || !keptAfter) {
                return checked;
            }
        }
        // Outside the block, the preview refuses.
        if ([editor openRange].location > 0) {
            XCTAssertFalse([editor allowsChangeInRange:NSMakeRange([editor openRange].location - 1, 1)]);
        }
        XCTAssertFalse([editor allowsChangeInRange:NSMakeRange(NSMaxRange([editor openRange]), 1)]);
        [editor closeBlock];
        checked += 1;
    }
    return checked;
}

- (void)testEditsInAnOpenParagraphChangeOnlyItsSource
{
    NSUInteger checked = [self checkMinimalEditsInMarkdown:[self corpusDocument] edits:40 seed:1];
    XCTAssertEqual(checked, (NSUInteger)7);
    checked = [self checkMinimalEditsInMarkdown:@"One.\r\n\r\nTwo\r\nlines.\r\n" edits:40 seed:2];
    XCTAssertEqual(checked, (NSUInteger)2);
}

// The property over the CommonMark spec's examples: every paragraph the
// renderer lists, opened and edited.
- (void)testEditsInEveryParagraphOfTheSpecExamplesChangeOnlyTheirSource
{
    NSString *path = [[NSString stringWithUTF8String:OM_SPEC_DIR] stringByAppendingPathComponent:@"spec.txt"];
    NSArray *examples = OMDTestSpecMarkdown(path);
    XCTAssertTrue([examples count] > 600, @"spec examples not found under %s", OM_SPEC_DIR);
    NSUInteger checked = 0;
    uint32_t seed = 11;
    for (NSString *markdown in examples) {
        checked += [self checkMinimalEditsInMarkdown:markdown edits:6 seed:seed++];
    }
    NSLog(@"#294 minimal-edit check: %lu paragraphs in %lu spec examples", (unsigned long)checked, (unsigned long)[examples count]);
    XCTAssertTrue(checked > 400);
}

// The rendered text of the index-th editable block of rendered.
static NSString *OMDTestRenderedBlock(NSAttributedString *rendered, NSString *containing, NSRange *range)
{
    NSUInteger at = [[rendered string] rangeOfString:containing].location;
    NSRange found = NSMakeRange(NSNotFound, 0);
    if (at == NSNotFound || OMDEditableBlockIndexAtCharacterIndex(rendered, at, &found) == NSNotFound) {
        return nil;
    }
    if (range != NULL) {
        *range = found;
    }
    return [[rendered string] substringWithRange:found];
}

// The source before the caret, for a caret just after `before` in the
// block's rendered text.
- (NSString *)sourceBeforeCaretAfter:(NSString *)before
                            inBlock:(NSString *)renderedBlock
                             source:(NSString *)blockSource
{
    NSRange at = [renderedBlock rangeOfString:before];
    XCTAssertTrue(at.location != NSNotFound, @"%@ not in %@", before, renderedBlock);
    if (at.location == NSNotFound) {
        return nil;
    }
    NSUInteger offset = OMDBlockSourceOffsetForRenderedOffset(renderedBlock, blockSource, NSMaxRange(at));
    return [blockSource substringToIndex:offset];
}

// Edit Block opens with the caret where it was in the rendered text.
- (void)testTheCaretKeepsItsPlaceInTheSource
{
    NSString *markdown = [self corpusDocument];
    OMMarkdownRenderer *renderer = [self renderer];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSArray *blocks = [renderer editableBlocks];
    XCTAssertEqual([blocks count], (NSUInteger)7);
    if ([blocks count] != 7) {
        return;
    }
    NSString *(^sourceOf)(NSUInteger) = ^NSString *(NSUInteger index) {
        NSRange range = [[[blocks objectAtIndex:index] objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];
        return [markdown substringWithRange:range];
    };

    NSString *plain = OMDTestRenderedBlock(rendered, @"A plain", NULL);
    NSString *plainSource = sourceOf(0);
    XCTAssertEqual(OMDBlockSourceOffsetForRenderedOffset(plain, plainSource, 0), (NSUInteger)0);
    XCTAssertEqual(OMDBlockSourceOffsetForRenderedOffset(plain, plainSource, [plain length]), [plainSource length]);
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"with " inBlock:plain source:plainSource], @"with "));
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"empha" inBlock:plain source:plainSource], @"*empha"));
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"cod" inBlock:plain source:plainSource], @"`cod"));
    // After the link, not inside its destination or title.
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"link a" inBlock:plain source:plainSource], @"\"t\") a"));
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"& an" inBlock:plain source:plainSource], @"&amp; an"));
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"second" inBlock:plain source:plainSource], @"\nIt wraps onto a second"));

    NSString *unicode = OMDTestRenderedBlock(rendered, @"Unicode", NULL);
    NSString *unicodeSource = sourceOf(1);
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"\U0001F600" inBlock:unicode source:unicodeSource], @"emoji \U0001F600"));
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"日本" inBlock:unicode source:unicodeSource], @"日本"));

    // The second line of a quote: after its marker.
    NSString *quote = OMDTestRenderedBlock(rendered, @"A quoted", NULL);
    NSString *quoteSource = sourceOf(4);
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"paragraph" inBlock:quote source:quoteSource], @"A quoted paragraph"));
    XCTAssertTrue(OMDTestEndsWith([self sourceBeforeCaretAfter:@"on" inBlock:quote source:quoteSource], @"> on"));
}

// Over the spec's paragraphs: the caret's place in the source never moves
// back as it moves on in the rendered text, and stays inside the block.
- (void)testTheCaretsPlaceInTheSourceMovesForwardWithIt
{
    NSString *path = [[NSString stringWithUTF8String:OM_SPEC_DIR] stringByAppendingPathComponent:@"spec.txt"];
    NSArray *examples = OMDTestSpecMarkdown(path);
    XCTAssertTrue([examples count] > 600);
    NSUInteger checked = 0;
    for (NSString *markdown in examples) {
        OMMarkdownRenderer *renderer = [self renderer];
        NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
        NSArray *blocks = [renderer editableBlocks];
        NSUInteger index = 0;
        NSUInteger blockIndex = 0;
        while (index < [rendered length] && blockIndex < [blocks count]) {
            NSRange run = NSMakeRange(index, 1);
            id value = [rendered attribute:OMMarkdownRendererEditableBlockAttributeName atIndex:index
                     longestEffectiveRange:&run inRange:NSMakeRange(0, [rendered length])];
            if (value != nil) {
                NSString *text = [[rendered string] substringWithRange:run];
                NSRange sourceRange = [[[blocks objectAtIndex:blockIndex] objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];
                NSString *source = [markdown substringWithRange:sourceRange];
                NSUInteger previous = 0;
                for (NSUInteger offset = 0; offset <= [text length]; offset++) {
                    NSUInteger at = OMDBlockSourceOffsetForRenderedOffset(text, source, offset);
                    XCTAssertTrue(at >= previous && at <= [source length],
                                  @"offset %lu -> %lu (previous %lu) in %@ / %@",
                                  (unsigned long)offset, (unsigned long)at, (unsigned long)previous, text, source);
                    previous = at;
                }
                checked += 1;
                blockIndex += 1;
            }
            index = NSMaxRange(run) > index ? NSMaxRange(run) : index + 1;
        }
    }
    XCTAssertTrue(checked > 400);
}

// An edit that touches text outside the open block (here, made directly on
// the storage, as no view would allow it) marks the editor out of sync
// instead of changing the source.
- (void)testAnEditOutsideTheBlockIsNotMirrored
{
    NSString *markdown = @"First.\n\nSecond.\n";
    OMMarkdownRenderer *renderer = [self renderer];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];
    NSRange renderedRange = NSMakeRange(NSNotFound, 0);
    NSUInteger index = OMDEditableBlockIndexAtCharacterIndex(rendered, [[rendered string] rangeOfString:@"Second"].location, &renderedRange);
    XCTAssertEqual(index, (NSUInteger)1);
    NSRange sourceRange = [[[[renderer editableBlocks] objectAtIndex:1] objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];
    NSTextStorage *preview = [[[NSTextStorage alloc] initWithAttributedString:rendered] autorelease];
    OMDTestBlockSource *source = [[[OMDTestBlockSource alloc] initWithString:markdown] autorelease];
    OMDBlockEditor *editor = [[[OMDBlockEditor alloc] initWithPreviewStorage:preview source:source] autorelease];
    XCTAssertTrue([editor openBlockAtRenderedRange:renderedRange sourceRange:sourceRange attributes:nil]);
    [preview replaceCharactersInRange:NSMakeRange(0, 1) withString:@"f"];
    XCTAssertTrue([editor isOutOfSync]);
    XCTAssertEqualObjects(source->_text, markdown);
}

// The preview view: with a block open it is editable inside the block only.
// This is the spike's main question for GNUstep's text system (an editable
// sub-range of a non-editable view), asked without a window.
- (void)testPreviewViewTakesTypingOnlyInsideTheOpenBlock
{
    NSString *markdown = @"First *one*.\n\nSecond.\n";
    OMMarkdownRenderer *renderer = [self renderer];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:markdown];

    OMDTextView *view = [[[OMDTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)] autorelease];
    [view setEditable:NO];
    [view setSelectable:YES];
    [[view textStorage] setAttributedString:rendered];
    NSRange renderedRange = NSMakeRange(NSNotFound, 0);
    XCTAssertEqual(OMDEditableBlockIndexAtCharacterIndex([view textStorage], 0, &renderedRange), (NSUInteger)0);
    NSRange sourceRange = [[[[renderer editableBlocks] objectAtIndex:0] objectForKey:OMMarkdownRendererEditableBlockSourceRangeKey] rangeValue];

    OMDTestBlockSource *source = [[[OMDTestBlockSource alloc] initWithString:markdown] autorelease];
    OMDBlockEditor *editor = [[[OMDBlockEditor alloc] initWithPreviewStorage:[view textStorage] source:source] autorelease];
    XCTAssertTrue([editor openBlockAtRenderedRange:renderedRange sourceRange:sourceRange attributes:nil]);
    [view setBlockEditor:editor];
    [view setAllowsUndo:NO];
    [view setEditable:YES];
    XCTAssertEqualObjects([[view string] substringWithRange:[editor openRange]], @"First *one*.");

    // Typing inside: the preview and the source both change.
    [view setSelectedRange:NSMakeRange([editor openRange].location + 7, 0)];
    [view insertText:@"very "];
    XCTAssertEqualObjects(source->_text, @"First *very one*.\n\nSecond.\n");
    XCTAssertEqualObjects([[view string] substringWithRange:[editor openRange]], @"First *very one*.");

    // Deleting backwards from the block's end.
    [view setSelectedRange:NSMakeRange(NSMaxRange([editor openRange]), 0)];
    [view deleteBackward:nil];
    XCTAssertEqualObjects(source->_text, @"First *very one*\n\nSecond.\n");

    // Outside the block: refused, nothing changes.
    NSString *previewBefore = [[[view string] copy] autorelease];
    NSUInteger second = [[view string] rangeOfString:@"Second"].location;
    XCTAssertFalse([view shouldChangeTextInRange:NSMakeRange(second, 0) replacementString:@"x"]);
    [view setSelectedRange:NSMakeRange(second, 0)];
    [view insertText:@"x"];
    XCTAssertEqualObjects([view string], previewBefore);
    XCTAssertEqualObjects(source->_text, @"First *very one*\n\nSecond.\n");
    XCTAssertFalse([editor isOutOfSync]);

    // A selection reaching past the block can't be replaced either.
    [view setSelectedRange:NSMakeRange(NSMaxRange([editor openRange]) - 2, 4)];
    [view insertText:@"y"];
    XCTAssertEqualObjects(source->_text, @"First *very one*\n\nSecond.\n");

    [editor closeBlock];
    [view setBlockEditor:nil];
    [view setEditable:NO];
}

@end
