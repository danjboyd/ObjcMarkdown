// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMMarkdownRenderer.h"
#import "OMMarkdownParsingOptions.h"

#ifndef OM_SPEC_DIR
#define OM_SPEC_DIR "Spec"
#endif

// One example from a spec file.
@interface OMSpecExample : NSObject
{
@public
    NSString *_file;
    NSUInteger _number;
    NSString *_section;
    NSString *_markdown;
    NSString *_html;
}
@end

@implementation OMSpecExample
- (void)dealloc
{
    [_file release];
    [_section release];
    [_markdown release];
    [_html release];
    [super dealloc];
}
// "spec:123", the key used in known-failures.txt.
- (NSString *)key
{
    return [NSString stringWithFormat:@"%@:%lu", _file, (unsigned long)_number];
}
@end

static NSString * const OMSpecFence = @"````````````````````````````````";

// The examples in a spec file, numbered from 1, each with its section heading.
static NSArray *OMSpecExamplesInFile(NSString *path, NSString *name)
{
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (text == nil) {
        return nil;
    }
    NSMutableArray *examples = [NSMutableArray array];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSString *section = @"";
    NSUInteger index = 0;
    NSUInteger number = 0;
    while (index < [lines count]) {
        NSString *line = [lines objectAtIndex:index++];
        if ([line hasPrefix:@"#"]) {
            NSRange space = [line rangeOfString:@" "];
            if (space.location != NSNotFound) {
                section = [[line substringFromIndex:NSMaxRange(space)]
                           stringByReplacingOccurrencesOfString:@" (extension)" withString:@""];
            }
            continue;
        }
        if (![line hasPrefix:[OMSpecFence stringByAppendingString:@" example"]]) {
            continue;
        }
        NSMutableArray *markdown = [NSMutableArray array];
        NSMutableArray *html = [NSMutableArray array];
        NSMutableArray *target = markdown;
        while (index < [lines count]) {
            line = [lines objectAtIndex:index++];
            if ([line isEqualToString:OMSpecFence]) {
                break;
            }
            if (target == markdown && [line isEqualToString:@"."]) {
                target = html;
                continue;
            }
            [target addObject:line];
        }
        OMSpecExample *example = [[[OMSpecExample alloc] init] autorelease];
        example->_file = [name copy];
        example->_number = ++number;
        example->_section = [section copy];
        // The spec shows tabs as U+2192.
        NSString *arrow = @"→";
        example->_markdown = [[[[markdown componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"]
                               stringByReplacingOccurrencesOfString:arrow withString:@"\t"] copy];
        example->_html = [[[html componentsJoinedByString:@"\n"]
                           stringByReplacingOccurrencesOfString:arrow withString:@"\t"] copy];
        [examples addObject:example];
    }
    return examples;
}

// The HTML renderer escapes only these four; anything else is literal text.
static NSString *OMSpecDecodeHTMLText(NSString *html)
{
    NSString *text = [html stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    text = [text stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    text = [text stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    return [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

static NSString *OMSpecReplacingPattern(NSString *string, NSString *pattern, NSString *replacement)
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionDotMatchesLineSeparators
                                                                             error:NULL];
    return [regex stringByReplacingMatchesInString:string
                                           options:0
                                             range:NSMakeRange(0, [string length])
                                      withTemplate:replacement];
}

// The expected HTML's visible text: no tags, no images (their alt text is
// not shown as text).
static NSString *OMSpecVisibleTextOfHTML(NSString *html)
{
    // Footnote back-references are navigation, like list bullets.
    NSString *text = OMSpecReplacingPattern(html, @"<a [^>]*class=\"footnote-backref\"[^>]*>.*?</a>", @"");
    text = OMSpecReplacingPattern(text, @"<img[^>]*>", @"");
    text = OMSpecReplacingPattern(text, @"<[A-Za-z/!?][^>]*>", @"");
    return OMSpecDecodeHTMLText(text);
}

static NSString *OMSpecWithoutWhitespace(NSString *string)
{
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableString *result = [NSMutableString stringWithCapacity:[string length]];
    NSUInteger index = 0;
    for (; index < [string length]; index++) {
        unichar ch = [string characterAtIndex:index];
        if (![space characterIsMember:ch] && ch != NSAttachmentCharacter && ch != 0x00A0) {
            [result appendFormat:@"%C", ch];
        }
    }
    return result;
}

// Whether every character of needle appears in haystack, in order.
static BOOL OMSpecIsSubsequence(NSString *needle, NSString *haystack)
{
    NSUInteger at = 0;
    NSUInteger index = 0;
    for (; index < [needle length]; index++) {
        unichar ch = [needle characterAtIndex:index];
        while (at < [haystack length] && [haystack characterAtIndex:at] != ch) {
            at += 1;
        }
        if (at >= [haystack length]) {
            return NO;
        }
        at += 1;
    }
    return YES;
}

// Every rendered range matching text, whitespace runs matching any
// whitespace, at or after from.
static NSArray *OMSpecFindAllText(NSString *text, NSString *rendered, NSUInteger from)
{
    NSMutableArray *ranges = [NSMutableArray array];
    NSArray *words = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *escaped = [NSMutableArray array];
    for (NSString *word in words) {
        if ([word length] > 0) {
            [escaped addObject:[NSRegularExpression escapedPatternForString:word]];
        }
    }
    if ([escaped count] == 0 || from > [rendered length]) {
        return ranges;
    }
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[escaped componentsJoinedByString:@"\\s+"]
                                                                           options:0
                                                                             error:NULL];
    for (NSTextCheckingResult *match in [regex matchesInString:rendered options:0 range:NSMakeRange(from, [rendered length] - from)]) {
        [ranges addObject:[NSValue valueWithRange:[match range]]];
    }
    return ranges;
}

static BOOL OMSpecFontHasTrait(NSFont *font, NSFontTraitMask trait)
{
    return font != nil && ([[NSFontManager sharedFontManager] traitsOfFont:font] & trait) != 0;
}

static BOOL OMSpecFontIsMonospaced(NSFont *font)
{
    if (font == nil) {
        return NO;
    }
    NSString *name = [[font fontName] lowercaseString];
    return [font isFixedPitch] || [name rangeOfString:@"mono"].location != NSNotFound ||
           [name rangeOfString:@"courier"].location != NSNotFound;
}

// Whether the rendered characters in range have the style an element implies.
static BOOL OMSpecRangeHasStyle(NSAttributedString *rendered, NSRange range, NSString *element)
{
    NSDictionary *attributes = [rendered attributesAtIndex:range.location effectiveRange:NULL];
    NSFont *font = [attributes objectForKey:NSFontAttributeName];
    if ([element isEqualToString:@"em"]) {
        return OMSpecFontHasTrait(font, NSItalicFontMask) ||
               [[attributes objectForKey:NSObliquenessAttributeName] doubleValue] > 0.0;
    }
    if ([element isEqualToString:@"strong"]) {
        return OMSpecFontHasTrait(font, NSBoldFontMask);
    }
    if ([element isEqualToString:@"del"]) {
        return [[attributes objectForKey:NSStrikethroughStyleAttributeName] integerValue] != 0;
    }
    if ([element isEqualToString:@"code"] || [element isEqualToString:@"pre"]) {
        return OMSpecFontIsMonospaced(font);
    }
    if ([element isEqualToString:@"heading"]) {
        return [attributes objectForKey:OMMarkdownRendererHeadingAnchorAttributeName] != nil;
    }
    return YES;
}

// Relative links resolve against this, in the renderer and in the expectations.
static NSURL *OMSpecBaseURL(void)
{
    // A directory, as the viewer passes the document's folder.
    return [NSURL URLWithString:@"file:///spec/"];
}

static NSString *OMSpecLinkString(id link)
{
    if ([link isKindOfClass:[NSURL class]]) {
        return [(NSURL *)link absoluteString];
    }
    return [link description];
}

// url with "/" between an http(s) host and a query or fragment, or nil if
// it isn't one of those or already has a path.
static NSString *OMSpecURLStringWithRootPath(NSString *url)
{
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^(https?://[^/?#]*)([?#].*)$"
                                                                             options:NSRegularExpressionCaseInsensitive
                                                                               error:NULL];
    if (url == nil || [pattern numberOfMatchesInString:url options:0 range:NSMakeRange(0, [url length])] == 0) {
        return nil;
    }
    return [pattern stringByReplacingMatchesInString:url options:0 range:NSMakeRange(0, [url length])
                                        withTemplate:@"$1/$2"];
}

// Why the rendered text at found doesn't match the element (its check
// name), or nil. href is the expected destination for links.
static NSString *OMSpecElementFailure(NSAttributedString *rendered, NSRange found, NSString *kind, id href)
{
    if (![kind isEqualToString:@"link"]) {
        return OMSpecRangeHasStyle(rendered, found, kind) ? nil : kind;
    }
    id link = [rendered attribute:NSLinkAttributeName atIndex:found.location effectiveRange:NULL];
    if (link == nil) {
        return @"link";
    }
    NSString *expected = href;
    NSURL *resolved = [NSURL URLWithString:expected relativeToURL:OMSpecBaseURL()];
    NSRegularExpression *scheme = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z][A-Za-z0-9+.-]{1,31}:"
                                                                            options:0 error:NULL];
    BOOL absolute = [scheme numberOfMatchesInString:expected options:0 range:NSMakeRange(0, [expected length])] > 0;
    if (resolved != nil && !absolute && ![expected hasPrefix:@"#"]) {
        expected = [resolved absoluteString];
    }
    NSString *actual = OMSpecLinkString(link);
    // Schemes are case-insensitive, and NSURL may lowercase them.
    NSRange colon = [expected rangeOfString:@":"];
    if (absolute && colon.location != NSNotFound && [actual length] >= colon.location &&
        [[actual substringToIndex:colon.location] caseInsensitiveCompare:[expected substringToIndex:colon.location]] == NSOrderedSame) {
        actual = [[expected substringToIndex:colon.location] stringByAppendingString:[actual substringFromIndex:colon.location]];
    }
    NSString *decodedExpected = [expected stringByRemovingPercentEncoding];
    NSString *decodedActual = [actual stringByRemovingPercentEncoding];
    if ([actual isEqualToString:expected] || (decodedExpected != nil && [decodedExpected isEqualToString:decodedActual])) {
        return nil;
    }
    // "http://host?q" and "http://host/?q" are the same URL (RFC 3986, 6.2.3);
    // the renderer gives the second where NSURL won't parse the first.
    NSString *rootedExpected = OMSpecURLStringWithRootPath(decodedExpected);
    if (rootedExpected != nil && [rootedExpected isEqualToString:decodedActual]) {
        return nil;
    }
    return @"href";
}

// The checks example fails when rendered as rendered.
static NSArray *OMSpecFailedChecks(OMSpecExample *example, NSAttributedString *rendered)
{
    NSMutableOrderedSet *failed = [NSMutableOrderedSet orderedSet];
    NSString *string = [rendered string];
    if (!OMSpecIsSubsequence(OMSpecWithoutWhitespace(OMSpecVisibleTextOfHTML(example->_html)),
                             OMSpecWithoutWhitespace(string))) {
        [failed addObject:@"text"];
    }

    // Innermost elements only: their content holds no further tags.
    NSString *html = OMSpecReplacingPattern(example->_html, @"<a [^>]*class=\"footnote-backref\"[^>]*>.*?</a>", @"");
    NSMutableArray *elements = [NSMutableArray array];
    NSRegularExpression *pre = [NSRegularExpression regularExpressionWithPattern:@"<pre><code[^>]*>([^<]*)</code></pre>"
                                                                         options:0 error:NULL];
    NSRegularExpression *inline_ = [NSRegularExpression regularExpressionWithPattern:@"<(em|strong|del|code|h[1-6])>([^<]*)</\\1>"
                                                                             options:0 error:NULL];
    NSRegularExpression *anchor = [NSRegularExpression regularExpressionWithPattern:@"<a href=\"([^\"]*)\"[^>]*>([^<]*)</a>"
                                                                            options:0 error:NULL];
    NSMutableIndexSet *inPre = [NSMutableIndexSet indexSet];
    for (NSTextCheckingResult *match in [pre matchesInString:html options:0 range:NSMakeRange(0, [html length])]) {
        [inPre addIndexesInRange:[match range]];
        [elements addObject:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:[match range].location],
                             @"pre", [html substringWithRange:[match rangeAtIndex:1]], [NSNull null], nil]];
    }
    for (NSTextCheckingResult *match in [inline_ matchesInString:html options:0 range:NSMakeRange(0, [html length])]) {
        if ([inPre containsIndex:[match range].location]) {
            continue;
        }
        NSString *element = [html substringWithRange:[match rangeAtIndex:1]];
        if ([element hasPrefix:@"h"]) {
            element = @"heading";
        }
        [elements addObject:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:[match range].location],
                             element, [html substringWithRange:[match rangeAtIndex:2]], [NSNull null], nil]];
    }
    for (NSTextCheckingResult *match in [anchor matchesInString:html options:0 range:NSMakeRange(0, [html length])]) {
        [elements addObject:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:[match range].location],
                             @"link", [html substringWithRange:[match rangeAtIndex:2]],
                             OMSpecDecodeHTMLText([html substringWithRange:[match rangeAtIndex:1]]), nil]];
    }
    [elements sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        return [[a objectAtIndex:0] compare:[b objectAtIndex:0]];
    }];

    NSUInteger cursor = 0;
    for (NSArray *element in elements) {
        NSString *kind = [element objectAtIndex:1];
        NSString *text = OMSpecDecodeHTMLText([element objectAtIndex:2]);
        if ([[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            continue;
        }
        // The first occurrence (from the cursor, else anywhere) that passes;
        // the same text often appears unstyled elsewhere in the example.
        NSArray *candidates = OMSpecFindAllText(text, string, cursor);
        if ([candidates count] == 0) {
            candidates = OMSpecFindAllText(text, string, 0);
        }
        if ([candidates count] == 0) {
            [failed addObject:kind];
            continue;
        }
        NSString *failure = nil;
        for (NSValue *value in candidates) {
            NSRange found = [value rangeValue];
            failure = OMSpecElementFailure(rendered, found, kind, [element objectAtIndex:3]);
            if (failure == nil) {
                cursor = NSMaxRange(found);
                break;
            }
        }
        if (failure != nil) {
            [failed addObject:failure];
        }
    }
    return [failed array];
}

@interface OMSpecConformanceTests : XCTestCase
@end

@implementation OMSpecConformanceTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (NSString *)specPath:(NSString *)name
{
    return [[NSString stringWithUTF8String:OM_SPEC_DIR] stringByAppendingPathComponent:name];
}

// known-failures.txt: "spec:123 text em  # reason", blank lines and "#" comments allowed.
- (NSDictionary *)knownFailures
{
    NSString *text = [NSString stringWithContentsOfFile:[self specPath:@"known-failures.txt"]
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
    NSMutableDictionary *known = [NSMutableDictionary dictionary];
    for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = rawLine;
        NSRange comment = [line rangeOfString:@"#"];
        if (comment.location != NSNotFound) {
            line = [line substringToIndex:comment.location];
        }
        NSMutableArray *words = [NSMutableArray array];
        for (NSString *word in [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
            if ([word length] > 0) {
                [words addObject:word];
            }
        }
        if ([words count] >= 2) {
            [known setObject:[NSSet setWithArray:[words subarrayWithRange:NSMakeRange(1, [words count] - 1)]]
                      forKey:[words objectAtIndex:0]];
        }
    }
    return known;
}

- (OMMarkdownRenderer *)specRenderer
{
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    // Plain CommonMark/GFM: "$" is literal text in the spec.
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyDisabled];
    // The spec's expected output passes raw HTML through as it is; only
    // HTML shown as text matches that (the safe subset renders it, #65).
    [options setInlineHTMLPolicy:OMMarkdownHTMLPolicyRenderAsText];
    [options setBlockHTMLPolicy:OMMarkdownHTMLPolicyRenderAsText];
    [options setAllowRemoteImages:NO];
    [options setBaseURL:OMSpecBaseURL()];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:nil parsingOptions:options] autorelease];
    [renderer setLayoutWidth:800.0];
    return renderer;
}

- (void)testSpecFileParsing
{
    NSArray *spec = OMSpecExamplesInFile([self specPath:@"spec.txt"], @"spec");
    XCTAssertEqual([spec count], (NSUInteger)672);
    OMSpecExample *first = [spec firstObject];
    XCTAssertEqualObjects(first->_markdown, @"\tfoo\tbaz\t\tbim\n");
    XCTAssertEqualObjects(first->_html, @"<pre><code>foo\tbaz\t\tbim\n</code></pre>");
    XCTAssertEqualObjects(first->_section, @"Tabs");
    XCTAssertEqual([OMSpecExamplesInFile([self specPath:@"extensions.txt"], @"extensions") count], (NSUInteger)30);
}

- (void)testCheckerSeesStylesTextAndLinks
{
    OMMarkdownRenderer *renderer = [self specRenderer];
    OMSpecExample *example = [[[OMSpecExample alloc] init] autorelease];
    example->_html = [@"<p><em>a</em> <strong>b</strong> <code>c</code> <a href=\"/u\">d</a></p>" retain];
    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:@"*a* **b** `c` [d](/u)\n"];
    XCTAssertEqualObjects(OMSpecFailedChecks(example, rendered), [NSArray array]);
    rendered = [renderer attributedStringFromMarkdown:@"a b c d\n"];
    NSArray *expected = [NSArray arrayWithObjects:@"em", @"strong", @"code", @"link", nil];
    XCTAssertEqualObjects(OMSpecFailedChecks(example, rendered), expected);
    rendered = [renderer attributedStringFromMarkdown:@"*a*\n"];
    XCTAssertTrue([OMSpecFailedChecks(example, rendered) containsObject:@"text"]);
}

- (void)testSpecExamplesHaveNoNewFailures
{
    NSMutableArray *examples = [NSMutableArray array];
    [examples addObjectsFromArray:OMSpecExamplesInFile([self specPath:@"spec.txt"], @"spec")];
    [examples addObjectsFromArray:OMSpecExamplesInFile([self specPath:@"extensions.txt"], @"extensions")];
    XCTAssertTrue([examples count] > 600, @"spec files not found under %s", OM_SPEC_DIR);

    NSDictionary *known = [self knownFailures];
    OMMarkdownRenderer *renderer = [self specRenderer];
    NSMutableArray *regressions = [NSMutableArray array];
    NSMutableArray *nowPassing = [NSMutableArray array];
    NSMutableString *currentList = [NSMutableString string];
    NSMutableArray *sectionOrder = [NSMutableArray array];
    NSMutableDictionary *sectionTotals = [NSMutableDictionary dictionary];
    NSMutableDictionary *sectionPasses = [NSMutableDictionary dictionary];
    NSCountedSet *checkFailures = [NSCountedSet set];
    NSUInteger passed = 0;

    for (OMSpecExample *example in examples) {
        NSArray *failed = nil;
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        @try {
            NSAttributedString *rendered = [renderer attributedStringFromMarkdown:example->_markdown];
            failed = rendered != nil ? OMSpecFailedChecks(example, rendered) : [NSArray arrayWithObject:@"crash"];
        } @catch (NSException *exception) {
            failed = [NSArray arrayWithObject:@"crash"];
        }
        [failed retain];
        [pool release];
        [failed autorelease];

        NSString *key = [example key];
        NSSet *expected = [known objectForKey:key];
        for (NSString *check in failed) {
            [checkFailures addObject:check];
            if (![expected containsObject:check]) {
                [regressions addObject:[NSString stringWithFormat:@"%@ %@ (%@)", key, check, example->_section]];
            }
        }
        for (NSString *check in expected) {
            if (![failed containsObject:check]) {
                [nowPassing addObject:[NSString stringWithFormat:@"%@ %@", key, check]];
            }
        }
        if ([failed count] > 0) {
            [currentList appendFormat:@"%@ %@  # %@\n", key, [failed componentsJoinedByString:@" "], example->_section];
        } else {
            passed += 1;
        }

        NSString *section = [NSString stringWithFormat:@"%@: %@", example->_file, example->_section];
        if ([sectionTotals objectForKey:section] == nil) {
            [sectionOrder addObject:section];
        }
        [sectionTotals setObject:[NSNumber numberWithUnsignedInteger:[[sectionTotals objectForKey:section] unsignedIntegerValue] + 1]
                          forKey:section];
        if ([failed count] == 0) {
            [sectionPasses setObject:[NSNumber numberWithUnsignedInteger:[[sectionPasses objectForKey:section] unsignedIntegerValue] + 1]
                              forKey:section];
        }
    }

    NSMutableString *report = [NSMutableString stringWithFormat:@"Spec conformance: %lu of %lu examples pass every check (%.1f%%)\n",
                               (unsigned long)passed, (unsigned long)[examples count],
                               [examples count] > 0 ? 100.0 * passed / [examples count] : 0.0];
    for (NSString *section in sectionOrder) {
        [report appendFormat:@"  %3lu/%-3lu %@\n",
         (unsigned long)[[sectionPasses objectForKey:section] unsignedIntegerValue],
         (unsigned long)[[sectionTotals objectForKey:section] unsignedIntegerValue], section];
    }
    for (NSString *check in [[checkFailures allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
        [report appendFormat:@"  failing %@: %lu\n", check, (unsigned long)[checkFailures countForObject:check]];
    }
    NSLog(@"%@", report);
    if ([nowPassing count] > 0) {
        NSLog(@"Spec conformance: %lu known failures now pass; trim known-failures.txt:\n%@",
              (unsigned long)[nowPassing count], [nowPassing componentsJoinedByString:@"\n"]);
    }

    const char *writePath = getenv("OM_SPEC_WRITE_KNOWN_FAILURES");
    if (writePath != NULL && writePath[0] != '\0') {
        NSString *header = @"# Checks each spec example is known to fail (see README.md).\n"
                           @"# Format: <file>:<example> <check>...  # <section>\n";
        [[header stringByAppendingString:currentList] writeToFile:[NSString stringWithUTF8String:writePath]
                                                       atomically:YES
                                                         encoding:NSUTF8StringEncoding
                                                            error:NULL];
        return;
    }
    XCTAssertEqual([regressions count], (NSUInteger)0, @"new spec failures:\n%@",
                   [[regressions subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)40, [regressions count]))]
                    componentsJoinedByString:@"\n"]);
}

@end
