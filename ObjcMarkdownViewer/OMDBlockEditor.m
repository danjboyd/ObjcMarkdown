// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDBlockEditor.h"
#import "OMMarkdownRenderer.h"

#include <stdint.h>
#include <stdlib.h>

NSString * const OMDOpenBlockAttributeName = @"OMDOpenBlock";

NSUInteger OMDEditableBlockIndexAtCharacterIndex(NSAttributedString *text,
                                                 NSUInteger characterIndex,
                                                 NSRange *renderedRange)
{
    NSUInteger length = [text length];
    if (text == nil || length == 0 || characterIndex == NSNotFound || characterIndex > length) {
        return NSNotFound;
    }
    NSUInteger probe = characterIndex;
    if (probe == length ||
        [text attribute:OMMarkdownRendererEditableBlockAttributeName atIndex:probe effectiveRange:NULL] == nil) {
        // A caret just after a block's last character.
        if (probe == 0 ||
            [text attribute:OMMarkdownRendererEditableBlockAttributeName atIndex:probe - 1 effectiveRange:NULL] == nil) {
            return NSNotFound;
        }
        probe -= 1;
    }
    // Count the blocks' runs up to the one holding probe.
    NSUInteger count = 0;
    NSUInteger index = 0;
    while (index < length) {
        NSRange run = NSMakeRange(index, 1);
        id value = [text attribute:OMMarkdownRendererEditableBlockAttributeName
                           atIndex:index
             longestEffectiveRange:&run
                           inRange:NSMakeRange(0, length)];
        if (value != nil) {
            if (probe < NSMaxRange(run)) {
                if (renderedRange != NULL) {
                    *renderedRange = run;
                }
                return count;
            }
            count += 1;
        }
        index = NSMaxRange(run) > index ? NSMaxRange(run) : index + 1;
    }
    return NSNotFound;
}

static BOOL OMDBlockCharacterIsSpace(unichar c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029 || c == 0x00A0;
}

static BOOL OMDBlockCharactersMatch(unichar rendered, unichar source)
{
    if (rendered == source) {
        return YES;
    }
    return OMDBlockCharacterIsSpace(rendered) && OMDBlockCharacterIsSpace(source);
}

// The rendered text is aligned with the source by a longest common
// subsequence, traced back from the end so that each character is matched
// as late as it can be: the space before "and" in "[link](u \"t\") and" is
// the one after the link, not the one inside it. Past the size limit, the
// characters are matched in order, each at its first match.
NSUInteger OMDBlockSourceOffsetForRenderedOffset(NSString *rendered,
                                                 NSString *source,
                                                 NSUInteger renderedOffset)
{
    NSUInteger n = [rendered length];
    NSUInteger m = [source length];
    if (renderedOffset > n) {
        renderedOffset = n;
    }
    if (renderedOffset == 0 || m == 0) {
        return 0;
    }
    const NSUInteger limit = 1500;
    if (n > limit || m > limit) {
        NSUInteger position = 0;
        for (NSUInteger r = 0; r < renderedOffset && position < m; r++) {
            unichar c = [rendered characterAtIndex:r];
            for (NSUInteger k = position; k < m; k++) {
                if (OMDBlockCharactersMatch(c, [source characterAtIndex:k])) {
                    position = k + 1;
                    break;
                }
            }
        }
        return position;
    }

    unichar *r = (unichar *)malloc(sizeof(unichar) * n);
    unichar *s = (unichar *)malloc(sizeof(unichar) * m);
    uint16_t *table = (uint16_t *)calloc((n + 1) * (m + 1), sizeof(uint16_t));
    if (r == NULL || s == NULL || table == NULL) {
        free(r);
        free(s);
        free(table);
        return 0;
    }
    [rendered getCharacters:r range:NSMakeRange(0, n)];
    [source getCharacters:s range:NSMakeRange(0, m)];
#define OMD_LCS(i, j) table[(i) * (m + 1) + (j)]
    for (NSUInteger i = 1; i <= n; i++) {
        for (NSUInteger j = 1; j <= m; j++) {
            if (OMDBlockCharactersMatch(r[i - 1], s[j - 1])) {
                OMD_LCS(i, j) = (uint16_t)(OMD_LCS(i - 1, j - 1) + 1);
            } else {
                uint16_t up = OMD_LCS(i - 1, j);
                uint16_t left = OMD_LCS(i, j - 1);
                OMD_LCS(i, j) = up > left ? up : left;
            }
        }
    }
    // The source position after the last rendered character before the
    // caret that has a match.
    NSUInteger result = 0;
    NSUInteger i = n;
    NSUInteger j = m;
    while (i > 0 && j > 0) {
        if (OMDBlockCharactersMatch(r[i - 1], s[j - 1]) &&
            OMD_LCS(i, j) == OMD_LCS(i - 1, j - 1) + 1) {
            if (i - 1 < renderedOffset) {
                result = j;
                break;
            }
            i -= 1;
            j -= 1;
        } else if (OMD_LCS(i, j - 1) >= OMD_LCS(i - 1, j)) {
            j -= 1;
        } else {
            i -= 1;
        }
    }
#undef OMD_LCS
    free(r);
    free(s);
    free(table);
    return result;
}

// The containers before a block's first character on its line (prefix),
// as the prefix of a continuation line: each quote's ">" (with up to three
// spaces before and one after) and each list item's width in spaces. NO
// if the prefix holds no container or isn't understood (a tab).
typedef struct {
    BOOL quote;
    NSUInteger width;
} OMDBlockContainer;

static BOOL OMDBlockContainersFromPrefix(NSString *prefix, OMDBlockContainer *containers,
                                         NSUInteger capacity, NSUInteger *count)
{
    NSUInteger length = [prefix length];
    NSUInteger index = 0;
    NSUInteger found = 0;
    while (index < length) {
        unichar c = [prefix characterAtIndex:index];
        if (c == '\t') {
            return NO;
        }
        NSUInteger start = index;
        while (index < length && [prefix characterAtIndex:index] == ' ' && index - start < 3) {
            index += 1;
        }
        if (index >= length) {
            // Spaces only: the indent of the text in the innermost
            // container, which a continuation line needn't repeat.
            break;
        }
        c = [prefix characterAtIndex:index];
        if (found >= capacity) {
            return NO;
        }
        if (c == '>') {
            index += 1;
            if (index < length && [prefix characterAtIndex:index] == ' ') {
                index += 1;
            }
            containers[found].quote = YES;
            containers[found].width = 0;
            found += 1;
            continue;
        }
        NSUInteger marker = index;
        if (c == '-' || c == '+' || c == '*') {
            index += 1;
        } else if (c >= '0' && c <= '9') {
            while (index < length && [prefix characterAtIndex:index] >= '0' &&
                   [prefix characterAtIndex:index] <= '9' && index - marker < 9) {
                index += 1;
            }
            if (index >= length || ([prefix characterAtIndex:index] != '.' && [prefix characterAtIndex:index] != ')')) {
                return NO;
            }
            index += 1;
        } else {
            return NO;
        }
        NSUInteger spaces = 0;
        while (index < length && [prefix characterAtIndex:index] == ' ') {
            index += 1;
            spaces += 1;
        }
        if (spaces == 0) {
            return NO;
        }
        containers[found].quote = NO;
        containers[found].width = index - start;
        found += 1;
    }
    *count = found;
    return found > 0;
}

// How much of line (from its start) is the containers' prefix: each
// quote's marker while there is one (a lazy line has none), each list
// item's indent up to its width, then the white space a paragraph's
// continuation line may start with.
static NSUInteger OMDBlockContinuationPrefixLength(NSString *source, NSUInteger lineStart, NSUInteger lineEnd,
                                                   const OMDBlockContainer *containers, NSUInteger count)
{
    NSUInteger index = lineStart;
    for (NSUInteger c = 0; c < count; c++) {
        if (containers[c].quote) {
            NSUInteger probe = index;
            while (probe < lineEnd && [source characterAtIndex:probe] == ' ' && probe - index < 3) {
                probe += 1;
            }
            if (probe >= lineEnd || [source characterAtIndex:probe] != '>') {
                break;
            }
            index = probe + 1;
            if (index < lineEnd && [source characterAtIndex:index] == ' ') {
                index += 1;
            }
        } else {
            NSUInteger probe = index;
            while (probe < lineEnd && [source characterAtIndex:probe] == ' ' && probe - index < containers[c].width) {
                probe += 1;
            }
            index = probe;
        }
    }
    while (index < lineEnd && ([source characterAtIndex:index] == ' ' || [source characterAtIndex:index] == '\t')) {
        index += 1;
    }
    return index - lineStart;
}

@implementation OMDBlockEditor

@synthesize open = _open;
@synthesize openRange = _openRange;
@synthesize sourceRange = _sourceRange;
@synthesize outOfSync = _outOfSync;
@synthesize originalSource = _originalSource;

- (instancetype)initWithPreviewStorage:(NSTextStorage *)previewStorage
                                source:(id<OMDBlockEditorSource>)source
{
    self = [super init];
    if (self != nil) {
        _previewStorage = [previewStorage retain];
        _source = source;
        _openRange = NSMakeRange(NSNotFound, 0);
        _sourceRange = NSMakeRange(NSNotFound, 0);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(previewStorageDidProcessEditing:)
                                                     name:NSTextStorageDidProcessEditingNotification
                                                   object:_previewStorage];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_previewStorage release];
    [_openText release];
    [_originalSource release];
    [_linePrefixes release];
    [_newLinePrefix release];
    [super dealloc];
}

- (BOOL)openBlockAtRenderedRange:(NSRange)renderedRange
                     sourceRange:(NSRange)sourceRange
                      attributes:(NSDictionary *)attributes
{
    NSString *sourceString = [_source blockEditorSourceString];
    if (_open || _previewStorage == nil || sourceString == nil ||
        renderedRange.location == NSNotFound || NSMaxRange(renderedRange) > [_previewStorage length] ||
        sourceRange.location == NSNotFound || NSMaxRange(sourceRange) > [sourceString length]) {
        return NO;
    }
    NSString *blockSource = [sourceString substringWithRange:sourceRange];
    NSMutableArray *prefixes = [NSMutableArray arrayWithObject:@""];
    NSMutableString *openText = [NSMutableString string];
    NSString *newLinePrefix = @"";
    // The first line's prefix: from its start to the block.
    NSUInteger lineStart = sourceRange.location;
    while (lineStart > 0) {
        unichar c = [sourceString characterAtIndex:lineStart - 1];
        if (c == '\n' || c == '\r') {
            break;
        }
        lineStart -= 1;
    }
    OMDBlockContainer containers[16];
    NSUInteger containerCount = 0;
    BOOL project = OMDBlockContainersFromPrefix([sourceString substringWithRange:NSMakeRange(lineStart, sourceRange.location - lineStart)],
                                                containers, 16, &containerCount);
    if (project) {
        NSMutableString *canonical = [NSMutableString string];
        for (NSUInteger c = 0; c < containerCount; c++) {
            if (containers[c].quote) {
                [canonical appendString:@"> "];
            } else {
                for (NSUInteger s = 0; s < containers[c].width; s++) {
                    [canonical appendString:@" "];
                }
            }
        }
        newLinePrefix = canonical;
        // Line by line: a line ends after its "\n" (a "\r\n" stays
        // whole, with the "\r" in the text before it).
        NSUInteger index = sourceRange.location;
        NSUInteger end = NSMaxRange(sourceRange);
        NSUInteger textStart = index;
        while (index < end) {
            unichar c = [sourceString characterAtIndex:index];
            index += 1;
            if (c == '\n') {
                [openText appendString:[sourceString substringWithRange:NSMakeRange(textStart, index - textStart)]];
                NSUInteger lineEnd = index;
                while (lineEnd < end && [sourceString characterAtIndex:lineEnd] != '\n' &&
                       [sourceString characterAtIndex:lineEnd] != '\r') {
                    lineEnd += 1;
                }
                NSUInteger prefixLength = OMDBlockContinuationPrefixLength(sourceString, index, lineEnd,
                                                                           containers, containerCount);
                [prefixes addObject:[sourceString substringWithRange:NSMakeRange(index, prefixLength)]];
                index += prefixLength;
                textStart = index;
            }
        }
        [openText appendString:[sourceString substringWithRange:NSMakeRange(textStart, end - textStart)]];
    } else {
        for (NSUInteger index = 0; index < [blockSource length]; index++) {
            if ([blockSource characterAtIndex:index] == '\n') {
                [prefixes addObject:@""];
            }
        }
        [openText setString:blockSource];
    }

    NSMutableDictionary *blockAttributes = [NSMutableDictionary dictionaryWithDictionary:(attributes != nil ? attributes : [NSDictionary dictionary])];
    [blockAttributes setObject:[NSNumber numberWithBool:YES] forKey:OMDOpenBlockAttributeName];
    NSAttributedString *block = [[[NSAttributedString alloc] initWithString:openText
                                                                 attributes:blockAttributes] autorelease];
    _updatingPreview = YES;
    [_previewStorage beginEditing];
    [_previewStorage replaceCharactersInRange:renderedRange withAttributedString:block];
    [_previewStorage endEditing];
    _updatingPreview = NO;
    _openRange = NSMakeRange(renderedRange.location, [block length]);
    _sourceRange = sourceRange;
    [_openText release];
    _openText = [[block string] mutableCopy];
    [_originalSource release];
    _originalSource = [blockSource copy];
    [_linePrefixes release];
    _linePrefixes = [prefixes mutableCopy];
    [_newLinePrefix release];
    _newLinePrefix = [newLinePrefix copy];
    _outOfSync = NO;
    _open = YES;
    return YES;
}

- (BOOL)allowsChangeInRange:(NSRange)range
{
    if (!_open || range.location == NSNotFound) {
        return NO;
    }
    return range.location >= _openRange.location && NSMaxRange(range) <= NSMaxRange(_openRange);
}

- (NSRange)closeBlock
{
    NSRange result = _sourceRange;
    _open = NO;
    _openRange = NSMakeRange(NSNotFound, 0);
    _sourceRange = NSMakeRange(NSNotFound, 0);
    [_openText release];
    _openText = nil;
    [_linePrefixes release];
    _linePrefixes = nil;
    return result;
}

// Every character edit of the preview, however it came (typing, paste,
// the preview's own undo), is mirrored here. The edit must touch the open
// block; the block's text before and after is compared, and only the part
// that differs is replaced in the source, so the edited range AppKit
// reports (which may cover more than what changed) doesn't matter.
- (void)previewStorageDidProcessEditing:(NSNotification *)notification
{
    (void)notification;
    if (!_open || _updatingPreview || ([_previewStorage editedMask] & NSTextStorageEditedCharacters) == 0) {
        return;
    }
    NSRange edited = [_previewStorage editedRange];
    NSInteger delta = [_previewStorage changeInLength];
    NSInteger oldEditedEnd = (NSInteger)NSMaxRange(edited) - delta;
    NSInteger newLength = (NSInteger)_openRange.length + delta;
    if (edited.location == NSNotFound ||
        oldEditedEnd < (NSInteger)_openRange.location ||
        edited.location > NSMaxRange(_openRange) ||
        newLength < 0 ||
        _openRange.location + (NSUInteger)newLength > [_previewStorage length]) {
        _outOfSync = YES;
        return;
    }
    NSString *now = [[_previewStorage string] substringWithRange:NSMakeRange(_openRange.location, (NSUInteger)newLength)];
    NSUInteger oldLength = [_openText length];
    NSUInteger nowLength = [now length];
    NSUInteger prefix = 0;
    while (prefix < oldLength && prefix < nowLength &&
           [_openText characterAtIndex:prefix] == [now characterAtIndex:prefix]) {
        prefix += 1;
    }
    NSUInteger suffix = 0;
    while (suffix < oldLength - prefix && suffix < nowLength - prefix &&
           [_openText characterAtIndex:oldLength - 1 - suffix] == [now characterAtIndex:nowLength - 1 - suffix]) {
        suffix += 1;
    }
    NSRange oldSpan = NSMakeRange(prefix, oldLength - prefix - suffix);
    NSRange newSpan = NSMakeRange(prefix, nowLength - prefix - suffix);
    NSInteger sourceDelta = 0;
    if (oldSpan.length > 0 || newSpan.length > 0) {
        // The span in the source: its ends past the markers of every line
        // that starts at or before them, so an inserted line start keeps
        // its line's markers and a removed line break takes the next
        // line's with it.
        NSUInteger sourceStart = [self sourceOffsetForOpenOffset:oldSpan.location];
        NSUInteger sourceEnd = [self sourceOffsetForOpenOffset:NSMaxRange(oldSpan)];
        NSString *inserted = [now substringWithRange:newSpan];
        NSString *sourceInserted = inserted;
        NSUInteger newLines = 0;
        if ([_newLinePrefix length] > 0) {
            NSMutableString *withMarkers = [NSMutableString string];
            for (NSUInteger index = 0; index < [inserted length]; index++) {
                unichar c = [inserted characterAtIndex:index];
                [withMarkers appendFormat:@"%C", c];
                if (c == '\n') {
                    [withMarkers appendString:_newLinePrefix];
                }
            }
            sourceInserted = withMarkers;
        }
        for (NSUInteger index = 0; index < [inserted length]; index++) {
            if ([inserted characterAtIndex:index] == '\n') {
                newLines += 1;
            }
        }
        NSRange sourceReplaced = NSMakeRange(_sourceRange.location + sourceStart, sourceEnd - sourceStart);
        if (![_source blockEditor:self
            replaceSourceCharactersInRange:sourceReplaced
                                withString:sourceInserted]) {
            _outOfSync = YES;
            return;
        }
        sourceDelta = (NSInteger)[sourceInserted length] - (NSInteger)sourceReplaced.length;
        // The lines that started inside the old span are gone; the new
        // span's lines start with the new-line markers.
        NSUInteger firstLine = [self lineOfOpenOffset:oldSpan.location];
        NSUInteger removedLines = [self lineOfOpenOffset:NSMaxRange(oldSpan)] - firstLine;
        [_linePrefixes removeObjectsInRange:NSMakeRange(firstLine + 1, removedLines)];
        for (NSUInteger line = 0; line < newLines; line++) {
            [_linePrefixes insertObject:_newLinePrefix atIndex:firstLine + 1];
        }
    }
    [_openText setString:now];
    _openRange.length = nowLength;
    _sourceRange.length = (NSUInteger)((NSInteger)_sourceRange.length + sourceDelta);
}

// The open text's line holding offset (a line starts after its "\n").
- (NSUInteger)lineOfOpenOffset:(NSUInteger)offset
{
    NSUInteger line = 0;
    NSUInteger length = [_openText length];
    for (NSUInteger index = 0; index < offset && index < length; index++) {
        if ([_openText characterAtIndex:index] == '\n') {
            line += 1;
        }
    }
    return line;
}

// Where an offset in the open text (as it was before the edit being
// mirrored) is in the block's source.
- (NSUInteger)sourceOffsetForOpenOffset:(NSUInteger)offset
{
    NSUInteger markers = 0;
    NSUInteger line = 0;
    NSUInteger length = [_openText length];
    for (NSUInteger index = 0; index < offset && index < length; index++) {
        if ([_openText characterAtIndex:index] == '\n') {
            line += 1;
            if (line < [_linePrefixes count]) {
                markers += [[_linePrefixes objectAtIndex:line] length];
            }
        }
    }
    return offset + markers;
}

- (NSString *)sourceForOpenText
{
    if (_openText == nil) {
        return nil;
    }
    NSMutableString *result = [NSMutableString string];
    NSUInteger line = 0;
    NSUInteger length = [_openText length];
    for (NSUInteger index = 0; index < length; index++) {
        unichar c = [_openText characterAtIndex:index];
        [result appendFormat:@"%C", c];
        if (c == '\n') {
            line += 1;
            if (line < [_linePrefixes count]) {
                [result appendString:[_linePrefixes objectAtIndex:line]];
            }
        }
    }
    return result;
}

@end
