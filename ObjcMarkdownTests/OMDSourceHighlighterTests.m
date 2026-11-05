// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import "OMDSourceHighlighter.h"

@interface OMDSourceHighlighterTests : XCTestCase
@end

// Tells a highlight state about each edit to a storage's characters, as
// the window controller does.
@interface OMDHighlightEditRecorder : NSObject
{
    OMDSourceHighlightState *_state;
}
- (instancetype)initWithState:(OMDSourceHighlightState *)state storage:(NSTextStorage *)storage;
- (void)stop;
@end

@implementation OMDHighlightEditRecorder

- (instancetype)initWithState:(OMDSourceHighlightState *)state storage:(NSTextStorage *)storage
{
    self = [super init];
    if (self != nil) {
        _state = [state retain];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(storageDidProcessEditing:)
                                                     name:NSTextStorageDidProcessEditingNotification
                                                   object:storage];
    }
    return self;
}

- (void)storageDidProcessEditing:(NSNotification *)notification
{
    NSTextStorage *storage = [notification object];
    if (([storage editedMask] & NSTextStorageEditedCharacters) != 0) {
        [_state noteEditedRange:[storage editedRange] changeInLength:[storage changeInLength]];
    }
}

- (void)stop
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_state release];
    [super dealloc];
}

@end

@implementation OMDSourceHighlighterTests

static NSColor *OMDColorAt(NSMutableAttributedString *string, NSString *needle)
{
    NSRange range = [[string string] rangeOfString:needle];
    if (range.location == NSNotFound) {
        return nil;
    }
    return [string attribute:NSForegroundColorAttributeName
                     atIndex:range.location
              effectiveRange:NULL];
}

- (void)testHighlightsPrimaryMarkdownTokens
{
    NSString *markdown = @"# Heading\n\nplain text\n- item one\nOpen [Link](https://example.com) and `code` plus $x+y$.\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.84 green:0.84 blue:0.84 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.17 green:0.18 blue:0.20 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSColor *headingColor = OMDColorAt(styled, @"Heading");
    NSColor *plainColor = OMDColorAt(styled, @"plain text");
    NSColor *listColor = OMDColorAt(styled, @"- item one");
    NSColor *linkColor = OMDColorAt(styled, @"[Link](https://example.com)");
    NSColor *codeColor = OMDColorAt(styled, @"`code`");
    NSColor *mathColor = OMDColorAt(styled, @"$x+y$");

    XCTAssertNotNil(headingColor);
    XCTAssertNotNil(plainColor);
    XCTAssertNotNil(listColor);
    XCTAssertNotNil(linkColor);
    XCTAssertNotNil(codeColor);
    XCTAssertNotNil(mathColor);

    XCTAssertTrue([plainColor isEqual:base]);
    XCTAssertFalse([headingColor isEqual:base]);
    XCTAssertFalse([listColor isEqual:base]);
    XCTAssertFalse([linkColor isEqual:base]);
    XCTAssertFalse([codeColor isEqual:base]);
    XCTAssertFalse([mathColor isEqual:base]);
}

// Source text gets no ligatures (#125): GNUstep would draw "fi" as U+FB01,
// one cell in a monospaced font, and shift the columns after it.
- (void)testHighlightTurnsOffLigatures
{
    NSString *markdown = @"# first\n\n    fifty | fish\n`final` and plain fi text\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSUInteger index = 0;
    while (index < [styled length]) {
        NSRange effective = NSMakeRange(0, 0);
        NSNumber *ligature = [styled attribute:NSLigatureAttributeName
                                       atIndex:index
                                effectiveRange:&effective];
        if (OMDSourceTextNeedsLigatureAttribute()) {
            XCTAssertNotNil(ligature, @"no ligature attribute at %lu", (unsigned long)index);
            XCTAssertEqual([ligature intValue], 0, @"ligatures on at %lu", (unsigned long)index);
        } else {
            // macOS: the source font has its ligatures off instead (#346).
            XCTAssertNil(ligature, @"ligature attribute at %lu", (unsigned long)index);
        }
        index = NSMaxRange(effective);
    }
}

#if !defined(GNUSTEP)
- (NSString *)glyphsOf346:(NSString *)text attributes:(NSDictionary *)attributes
{
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:text attributes:attributes] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(2000.0, 200.0)] autorelease];
    [layoutManager addTextContainer:container];
    [storage addLayoutManager:layoutManager];
    [layoutManager ensureLayoutForTextContainer:container];
    NSMutableString *glyphs = [NSMutableString string];
    NSUInteger index = 0;
    for (; index < [layoutManager numberOfGlyphs]; index++) {
        [glyphs appendFormat:@"%u@%.2f ", (unsigned)[layoutManager CGGlyphAtIndex:index],
                             [layoutManager locationForGlyphAtIndex:index].x];
    }
    return glyphs;
}

// The source font without ligatures draws the same glyphs, in the same
// places, as NSLigatureAttributeName = 0 did, in fonts that do form
// ligatures by default (#346).
- (void)testSourceFontWithoutLigaturesDrawsLikeTheAttribute
{
    NSString *text = @"office fluffy affirm ffl fi fl -> != === www";
    NSUInteger compared = 0;
    for (NSString *name in [NSArray arrayWithObjects:@"Hoefler Text", @"Baskerville", @"Palatino", @"Didot", nil]) {
        NSFont *font = [NSFont fontWithName:name size:13.0];
        if (font == nil) {
            continue;
        }
        NSString *attributeOff = [self glyphsOf346:text attributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                    font, NSFontAttributeName,
                                                                    [NSNumber numberWithInt:0], NSLigatureAttributeName, nil]];
        NSString *fontOff = [self glyphsOf346:text attributes:[NSDictionary dictionaryWithObject:OMDSourceFontWithoutLigatures(font)
                                                                                          forKey:NSFontAttributeName]];
        NSString *ligatures = [self glyphsOf346:text attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
        XCTAssertEqualObjects(fontOff, attributeOff, @"%@", name);
        XCTAssertFalse([ligatures isEqualToString:attributeOff], @"%@ formed no ligatures to turn off", name);
        compared += 1;
    }
    XCTAssertTrue(compared > 0, @"no font with ligatures to compare");
    NSFont *mono = [NSFont userFixedPitchFontOfSize:13.0];
    XCTAssertEqualObjects([OMDSourceFontWithoutLigatures(mono) fontName], [mono fontName]);
    XCTAssertEqual([OMDSourceFontWithoutLigatures(mono) pointSize], [mono pointSize]);
}
#endif

// Where markup overlaps, the colour is the one a pass sets last: link,
// bold, italic, math, inline code, then fenced lines (#346 sets each
// character's colour once, so the order must be kept by hand).
- (void)testOverlappingMarkupKeepsThePassOrder
{
    NSString *markdown = @"Solo `solo` and **solo** and *solo* and [solo](u) and $solo$.\n"
                          "Over **bold `codeA` bold** and [link `codeB` link](u) and *it [linkC](u) it* and **b $mathD$ b**.\n"
                          "- list **boldE** item\n"
                          "\n"
                          "```\n"
                          "[linkF](u) and **boldF**\n"
                          "```\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.10 green:0.10 blue:0.10 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.96 alpha:1.0];
    [OMDSourceHighlighter highlightAttributedString:styled baseTextColor:base backgroundColor:background];
    NSString *text = [styled string];
    NSColor *(^colorOf)(NSString *) = ^NSColor *(NSString *needle) {
        NSRange found = [text rangeOfString:needle];
        XCTAssertTrue(found.location != NSNotFound, @"%@", needle);
        return [styled attribute:NSForegroundColorAttributeName atIndex:found.location + 1 effectiveRange:NULL];
    };
    NSColor *code = colorOf(@"`solo`");
    NSColor *emphasis = colorOf(@"**solo**");
    NSColor *link = colorOf(@"[solo]");
    NSColor *math = colorOf(@"$solo$");
    XCTAssertFalse([code isEqual:base]);
    XCTAssertFalse([link isEqual:emphasis]);
    XCTAssertFalse([code isEqual:emphasis]);

    XCTAssertEqualObjects(colorOf(@"codeA"), code, @"inline code wins over bold");
    XCTAssertEqualObjects(colorOf(@"codeB"), code, @"inline code wins over a link");
    XCTAssertEqualObjects(colorOf(@"linkC"), emphasis, @"italic wins over a link");
    XCTAssertEqualObjects(colorOf(@"mathD"), math, @"math wins over bold");
    XCTAssertEqualObjects(colorOf(@"boldE"), emphasis, @"bold wins over a list line");
    XCTAssertEqualObjects(colorOf(@"linkF"), code, @"a fenced line wins over a link");
    XCTAssertEqualObjects(colorOf(@"boldF"), code, @"a fenced line wins over bold");
}

- (void)testFencedCodeWinsOverLinkHighlighting
{
    NSString *markdown = @"```md\n[not-a-link](x)\n```\n\n[real-link](y)\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.10 green:0.10 blue:0.10 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.96 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSRange fencedRange = [[styled string] rangeOfString:@"[not-a-link](x)"];
    NSRange normalRange = [[styled string] rangeOfString:@"[real-link](y)"];
    XCTAssertTrue(fencedRange.location != NSNotFound);
    XCTAssertTrue(normalRange.location != NSNotFound);

    NSColor *fencedColor = [styled attribute:NSForegroundColorAttributeName
                                     atIndex:fencedRange.location
                              effectiveRange:NULL];
    NSColor *normalLinkColor = [styled attribute:NSForegroundColorAttributeName
                                         atIndex:normalRange.location
                                  effectiveRange:NULL];
    XCTAssertNotNil(fencedColor);
    XCTAssertNotNil(normalLinkColor);
    XCTAssertFalse([fencedColor isEqual:base]);
    XCTAssertFalse([normalLinkColor isEqual:base]);
    XCTAssertFalse([fencedColor isEqual:normalLinkColor]);
}

- (void)testLargeDocumentHighlightingPerformanceGuardrail
{
    NSMutableString *markdown = [NSMutableString string];
    NSUInteger i = 0;
    for (; i < 1800; i++) {
        [markdown appendFormat:@"# Heading %lu\n", (unsigned long)i];
        [markdown appendString:@"- item alpha beta gamma\n"];
        [markdown appendString:@"Inline `code` with [link](https://example.com) and $x+y$.\n"];
        [markdown appendString:@"```swift\nlet n = 42\nprint(n)\n```\n\n"];
    }

    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.12 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.97 green:0.97 blue:0.97 alpha:1.0];

    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;

    XCTAssertTrue(elapsed < 6.0);
    XCTAssertTrue([styled length] == [markdown length]);
}

- (void)testIndentedCodeBlockUsesCodeColorViaParserStyles
{
    NSString *markdown = @"    int value = 42;\n\nplain text\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.15 green:0.15 blue:0.15 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.96 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background];

    NSColor *codeLineColor = OMDColorAt(styled, @"int value = 42");
    NSColor *plainColor = OMDColorAt(styled, @"plain text");
    XCTAssertNotNil(codeLineColor);
    XCTAssertNotNil(plainColor);
    XCTAssertFalse([codeLineColor isEqual:base]);
    XCTAssertTrue([plainColor isEqual:base]);
}

- (void)testHighlightOptionsAllowHighContrastAndAccentOverride
{
    NSString *markdown = @"# Heading\n[link](x)\n";
    NSMutableAttributedString *normal = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSMutableAttributedString *accented = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.85 green:0.85 blue:0.85 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.18 green:0.18 blue:0.20 alpha:1.0];
    NSColor *accent = [NSColor colorWithCalibratedRed:0.92 green:0.30 blue:0.22 alpha:1.0];

    [OMDSourceHighlighter highlightAttributedString:normal
                                      baseTextColor:base
                                    backgroundColor:background
                                            options:@{ OMDSourceHighlighterOptionHighContrast: @NO }
                                        targetRange:NSMakeRange(NSNotFound, 0)];
    [OMDSourceHighlighter highlightAttributedString:accented
                                      baseTextColor:base
                                    backgroundColor:background
                                            options:@{
                                                OMDSourceHighlighterOptionHighContrast: @YES,
                                                OMDSourceHighlighterOptionAccentColor: accent
                                            }
                                        targetRange:NSMakeRange(NSNotFound, 0)];

    NSColor *normalHeading = OMDColorAt(normal, @"Heading");
    NSColor *accentHeading = OMDColorAt(accented, @"Heading");
    NSColor *accentLink = OMDColorAt(accented, @"[link](x)");
    XCTAssertNotNil(normalHeading);
    XCTAssertNotNil(accentHeading);
    XCTAssertNotNil(accentLink);
    XCTAssertFalse([normalHeading isEqual:accentHeading]);
    XCTAssertTrue([accentHeading isEqual:accentLink]);
}

- (void)testTargetRangeHighlightOnlyTouchesRequestedSegment
{
    NSString *markdown = @"# first\n\n# second\n";
    NSMutableAttributedString *styled = [[[NSMutableAttributedString alloc] initWithString:markdown] autorelease];
    NSColor *base = [NSColor colorWithCalibratedRed:0.14 green:0.14 blue:0.14 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.96 alpha:1.0];

    [styled addAttribute:NSForegroundColorAttributeName value:base range:NSMakeRange(0, [styled length])];

    NSRange firstLine = [[styled string] lineRangeForRange:NSMakeRange(0, 0)];
    [OMDSourceHighlighter highlightAttributedString:styled
                                      baseTextColor:base
                                    backgroundColor:background
                                            options:nil
                                        targetRange:firstLine];

    NSColor *firstHeadingColor = OMDColorAt(styled, @"first");
    NSColor *secondHeadingColor = OMDColorAt(styled, @"second");
    XCTAssertNotNil(firstHeadingColor);
    XCTAssertNotNil(secondHeadingColor);
    XCTAssertFalse([firstHeadingColor isEqual:base]);
    XCTAssertTrue([secondHeadingColor isEqual:base]);
}

// The first index where a and b differ in colour or ligatures, or NSNotFound.
static NSUInteger OMDFirstColourDifference(NSAttributedString *a, NSAttributedString *b)
{
    NSUInteger length = [a length];
    if ([b length] != length) {
        return 0;
    }
    NSUInteger index = 0;
    while (index < length) {
        NSRange rangeA = NSMakeRange(index, 1);
        NSRange rangeB = NSMakeRange(index, 1);
        NSDictionary *attributesA = [a attributesAtIndex:index effectiveRange:&rangeA];
        NSDictionary *attributesB = [b attributesAtIndex:index effectiveRange:&rangeB];
        id colourA = [attributesA objectForKey:NSForegroundColorAttributeName];
        id colourB = [attributesB objectForKey:NSForegroundColorAttributeName];
        id ligatureA = [attributesA objectForKey:NSLigatureAttributeName];
        id ligatureB = [attributesB objectForKey:NSLigatureAttributeName];
        if (!(colourA == colourB || [colourA isEqual:colourB]) ||
            !(ligatureA == ligatureB || [ligatureA isEqual:ligatureB])) {
            return index;
        }
        index = MIN(NSMaxRange(rangeA), NSMaxRange(rangeB));
    }
    return NSNotFound;
}

static NSUInteger OMDNextRandom(unsigned long long *seed)
{
    *seed = *seed * 6364136223846793005ULL + 1442695040888963407ULL;
    return (NSUInteger)(*seed >> 33);
}

static NSString *OMDHighlightCorpusFile(NSString *relativePath)
{
    NSString *path = [[NSString stringWithUTF8String:OM_SPEC_DIR] stringByAppendingPathComponent:relativePath];
    return [NSString stringWithContentsOfFile:[path stringByStandardizingPath] encoding:NSUTF8StringEncoding error:NULL];
}

// Whole lines of text from about offset, about length characters.
static NSString *OMDLinesOfText(NSString *text, NSUInteger offset, NSUInteger length)
{
    if (offset >= [text length]) {
        return @"";
    }
    NSUInteger start = [text lineRangeForRange:NSMakeRange(offset, 0)].location;
    NSUInteger end = start + length;
    if (end >= [text length]) {
        end = [text length];
    } else {
        end = NSMaxRange([text lineRangeForRange:NSMakeRange(end, 0)]);
    }
    return [text substringWithRange:NSMakeRange(start, end - start)];
}

// An incremental pass (#333) colours the text just as a full pass would,
// over the spec, the extensions and the docs, through random edits, the
// ones that move fences, display math, lists and indented code among them.
- (void)testIncrementalColouringMatchesAFullPass
{
    NSString *spec = OMDHighlightCorpusFile(@"spec.txt");
    NSString *extensions = OMDHighlightCorpusFile(@"extensions.txt");
    XCTAssertNotNil(spec);
    XCTAssertNotNil(extensions);
    if (spec == nil || extensions == nil) {
        return;
    }
    NSMutableArray *documents = [NSMutableArray array];
    NSUInteger offset = 0;
    for (; offset < [spec length]; offset += 40000) {
        [documents addObject:OMDLinesOfText(spec, offset, 16000)];
    }
    [documents addObject:extensions];
    NSArray *docs = [NSArray arrayWithObjects:@"../../README.md", @"../../docs/read-edit-design.md",
                                              @"../../docs/showcase.md", nil];
    for (NSString *name in docs) {
        NSString *text = OMDHighlightCorpusFile(name);
        if (text != nil) {
            [documents addObject:text];
        }
    }
    [documents addObject:@"# Math\n\nText $x$ and\n\n$$\na = b\n\nc = d\n$$\n\n- one\n  more\n\n      code\n\n> quote\nlazy\n\n```\nfenced\n```\n\r\nCRLF line\r\n\r\nend\n"];

    NSMutableString *math = [NSMutableString string];
    NSUInteger block = 0;
    for (; block < 40; block++) {
        [math appendFormat:@"Text %lu with $x$ in it.\n\n$$\na_%lu = b\n\nc = d\n$$\n\n", (unsigned long)block,
                           (unsigned long)block];
    }
    [documents addObject:math];

    NSArray *snippets = [NSArray arrayWithObjects:@"x", @"word ", @" ", @"\n", @"\n\n", @"```", @"~~~", @"```c\n",
                                                  @"$$", @"$", @"$x$", @"- ", @"* ", @"1. ", @"> ", @"    ", @"\t",
                                                  @"# ", @"## ", @"*", @"**", @"_", @"`", @"[a](b)", @"<div>\n",
                                                  @"===\n", @"---\n", @"\r\n", @"\r", @"|a|b|\n|-|-|\n", nil];
    NSColor *base = [NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    NSColor *background = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    unsigned long long seed = 333;
    const char *seedText = getenv("OMD_HIGHLIGHT_SEED");
    if (seedText != NULL) {
        seed = strtoull(seedText, NULL, 10);
    }
    NSUInteger passes = 0;
    NSUInteger partialPasses = 0;

    NSUInteger documentIndex = 0;
    for (; documentIndex < [documents count]; documentIndex++) {
        NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:[documents objectAtIndex:documentIndex]] autorelease];
        OMDSourceHighlightState *state = [[[OMDSourceHighlightState alloc] init] autorelease];
        OMDHighlightEditRecorder *recorder =
            [[[OMDHighlightEditRecorder alloc] initWithState:state storage:storage] autorelease];
        [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background
                                           options:nil state:state];
        NSUInteger hot = OMDNextRandom(&seed) % ([storage length] + 1);
        NSUInteger step = 0;
        for (; step < 50; step++) {
            NSMutableString *log = [NSMutableString string];
            NSUInteger edits = 1 + (OMDNextRandom(&seed) % 4 == 0 ? OMDNextRandom(&seed) % 3 : 0);
            NSUInteger e = 0;
            for (; e < edits; e++) {
                NSUInteger length = [storage length];
                if (OMDNextRandom(&seed) % 5 == 0) {
                    hot = OMDNextRandom(&seed) % (length + 1);
                }
                NSUInteger at = hot + (OMDNextRandom(&seed) % 41);
                at = at > 20 ? at - 20 : 0;
                if (at > length) {
                    at = length;
                }
                NSUInteger removed = 0;
                NSString *inserted = @"";
                NSUInteger op = OMDNextRandom(&seed) % 3;
                if (op != 0) {
                    removed = OMDNextRandom(&seed) % 12;
                    if (removed > length - at) {
                        removed = length - at;
                    }
                }
                if (op != 1) {
                    // Mostly typing; a structural snippet one edit in three.
                    if (OMDNextRandom(&seed) % 3 != 0) {
                        inserted = (OMDNextRandom(&seed) % 2 == 0) ? @"x" : @"word ";
                    } else {
                        inserted = [snippets objectAtIndex:OMDNextRandom(&seed) % [snippets count]];
                    }
                }
                [storage replaceCharactersInRange:NSMakeRange(at, removed) withString:inserted];
                [log appendFormat:@" {%lu,%lu}<-%@", (unsigned long)at, (unsigned long)removed,
                                  [inserted stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]];
                hot = at + [inserted length];
            }
            NSRange coloured = [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base
                                                          backgroundColor:background options:nil state:state];
            passes += 1;
            if (coloured.location == NSNotFound || coloured.length < [storage length]) {
                partialPasses += 1;
            }
            NSMutableAttributedString *expected =
                [[[NSMutableAttributedString alloc] initWithString:[storage string]] autorelease];
            [OMDSourceHighlighter highlightAttributedString:expected baseTextColor:base backgroundColor:background];
            NSUInteger difference = OMDFirstColourDifference(storage, expected);
            if (difference != NSNotFound) {
                NSString *around = OMDLinesOfText([storage string], difference > 80 ? difference - 80 : 0, 160);
                XCTFail(@"document %lu step %lu edits%@: colours differ at %lu, coloured %@, near:\n%@",
                        (unsigned long)documentIndex, (unsigned long)step, log, (unsigned long)difference,
                        NSStringFromRange(coloured), around);
                break;
            }
        }
        [recorder stop];
    }
    // Most passes are partial; the rest fell back to a full pass. (A lone
    // \r, once typed, makes every later pass of that document full.)
    XCTAssertTrue(partialPasses * 2 > passes, @"%lu of %lu passes partial",
                  (unsigned long)partialPasses, (unsigned long)passes);
}

// Typing in plain text recolours only its paragraph; opening a fence
// recolours what follows it; other colours or a reset, the whole text.
- (void)testIncrementalColouringRecoloursOnlyWhatItMust
{
    NSMutableString *markdown = [NSMutableString string];
    NSUInteger i = 0;
    for (; i < 50; i++) {
        [markdown appendFormat:@"Paragraph %lu with `code`.\n\n", (unsigned long)i];
    }
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:markdown] autorelease];
    OMDSourceHighlightState *state = [[[OMDSourceHighlightState alloc] init] autorelease];
    NSColor *base = [NSColor blackColor];
    NSColor *background = [NSColor whiteColor];
    NSRange coloured = [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base
                                                  backgroundColor:background options:nil state:state];
    XCTAssertEqual(coloured.length, [storage length]);

    // Nothing changed: nothing to colour.
    coloured = [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base
                                          backgroundColor:background options:nil state:state];
    XCTAssertEqual(coloured.location, (NSUInteger)NSNotFound);

    NSUInteger at = [[storage string] rangeOfString:@"Paragraph 20 "].location + 3;
    [storage replaceCharactersInRange:NSMakeRange(at, 0) withString:@"x"];
    [state noteEditedRange:NSMakeRange(at, 1) changeInLength:1];
    coloured = [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base
                                          backgroundColor:background options:nil state:state];
    XCTAssertTrue(coloured.location != NSNotFound && coloured.length < 100, @"%@", NSStringFromRange(coloured));
    XCTAssertTrue(NSLocationInRange(at, coloured));

    at = [[storage string] rangeOfString:@"Paragraph 30 "].location;
    [storage replaceCharactersInRange:NSMakeRange(at, 0) withString:@"```\n"];
    [state noteEditedRange:NSMakeRange(at, 4) changeInLength:4];
    coloured = [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base
                                          backgroundColor:background options:nil state:state];
    XCTAssertTrue(NSMaxRange(coloured) == [storage length], @"%@", NSStringFromRange(coloured));

    // Other colours: the whole text, even with nothing edited.
    coloured = [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base
                                          backgroundColor:[NSColor blackColor] options:nil state:state];
    XCTAssertEqual(coloured.length, [storage length]);

    [state reset];
    coloured = [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base
                                          backgroundColor:[NSColor blackColor] options:nil state:state];
    XCTAssertEqual(coloured.length, [storage length]);
}

// Display math pairs $$ across the whole text: a $$ typed in one paragraph
// recolours the math after it, outside the edited lines.
- (void)testIncrementalColouringFollowsDisplayMathPairing
{
    NSString *markdown = @"Intro\n\n$$\na = b\n$$\n\nMiddle text\n\n$$\nc = d\n$$\n\nAfter $$ e $$ end\n";
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:markdown] autorelease];
    OMDSourceHighlightState *state = [[[OMDSourceHighlightState alloc] init] autorelease];
    NSColor *base = [NSColor blackColor];
    NSColor *background = [NSColor whiteColor];
    [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background
                                       options:nil state:state];
    NSUInteger at = [[storage string] rangeOfString:@"Middle"].location + 3;
    [storage replaceCharactersInRange:NSMakeRange(at, 0) withString:@"$$"];
    [state noteEditedRange:NSMakeRange(at, 2) changeInLength:2];
    [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background
                                       options:nil state:state];
    NSMutableAttributedString *expected =
        [[[NSMutableAttributedString alloc] initWithString:[storage string]] autorelease];
    [OMDSourceHighlighter highlightAttributedString:expected baseTextColor:base backgroundColor:background];
    XCTAssertEqual(OMDFirstColourDifference(storage, expected), (NSUInteger)NSNotFound);
}

// Not a check: with OMD_HIGHLIGHT_TIMING set, prints what one colouring pass
// costs by document size, with no window (#164, #333): a full pass with
// nothing changed, a full pass after a typed letter, and an incremental pass
// after a typed letter. Compare builds by these.
- (void)testPrintHighlightTimings
{
    if (getenv("OMD_HIGHLIGHT_TIMING") == NULL) {
        return;
    }
    NSString *block = @"# A heading\n\nA paragraph with **bold**, *italic*, `code` and a [link](https://example.com).\n\n- one\n- two\n\n```c\nint main(void) { return 0; }\n```\n\n";
    NSUInteger sizes[] = { 200, 2000, 20000, 100000 };
    NSUInteger s = 0;
    for (; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
        NSMutableString *text = [NSMutableString string];
        while ([text length] < sizes[s]) {
            [text appendString:block];
        }
        NSTextStorage *storage = [[[NSTextStorage alloc] initWithString:text] autorelease];
        NSColor *base = [NSColor blackColor];
        NSColor *background = [NSColor whiteColor];
        [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
        NSUInteger reps = 15;
        NSDate *start = [NSDate date];
        NSUInteger r = 0;
        for (; r < reps; r++) {
            [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
        }
        double repeat = -[start timeIntervalSinceNow] * 1000.0 / reps;
        start = [NSDate date];
        for (r = 0; r < reps; r++) {
            [storage replaceCharactersInRange:NSMakeRange([storage length] / 2, 0) withString:@"x"];
            [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background];
        }
        double typed = -[start timeIntervalSinceNow] * 1000.0 / reps;
        OMDSourceHighlightState *state = [[[OMDSourceHighlightState alloc] init] autorelease];
        [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background
                                           options:nil state:state];
        start = [NSDate date];
        for (r = 0; r < reps; r++) {
            NSUInteger at = [storage length] / 2;
            [storage replaceCharactersInRange:NSMakeRange(at, 0) withString:@"x"];
            [state noteEditedRange:NSMakeRange(at, 1) changeInLength:1];
            [OMDSourceHighlighter highlightTextStorage:storage baseTextColor:base backgroundColor:background
                                               options:nil state:state];
        }
        double incremental = -[start timeIntervalSinceNow] * 1000.0 / reps;
        NSLog(@"OMDHighlightTiming chars=%lu repeat=%.2fms typed=%.2fms incremental=%.2fms",
              (unsigned long)[storage length], repeat, typed, incremental);
    }
}

@end
