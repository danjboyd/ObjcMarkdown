// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDPreviewTextUpdate.h"
#import "OMRenderedObject.h"
#import "OMTextTable.h"

enum { OMDCompareChunkLength = 4096 };

// How attributes are compared. Before an edit nothing moves; after it,
// rendered objects keep their content but their source positions shift,
// and those comparisons collect the old objects to update.
typedef struct {
    BOOL ignorePositions;
    NSMutableArray *positionUpdates; // old object, new object, ...
} OMDCompareContext;

static BOOL OMDStringsEqual(NSString *a, NSString *b)
{
    return a == b || (a != nil && b != nil && [a isEqualToString:b]);
}

static BOOL OMDRenderedObjectsEquivalent(OMRenderedObject *a, OMRenderedObject *b, OMDCompareContext *context)
{
    if ([a kind] != [b kind] || !OMDStringsEqual([a source], [b source]) ||
        !OMDStringsEqual([a markdown], [b markdown])) {
        return NO;
    }
    if (NSEqualRanges([a sourceLineRange], [b sourceLineRange]) &&
        NSEqualRanges([a sourceRange], [b sourceRange])) {
        return YES;
    }
    if (context == NULL || !context->ignorePositions) {
        return NO;
    }
    [context->positionUpdates addObject:a];
    [context->positionUpdates addObject:b];
    return YES;
}

static BOOL OMDColorsEqual(NSColor *a, NSColor *b)
{
    return a == b || [a isEqual:b];
}

static BOOL OMDTextTablesEquivalent(OMTextTable *a, OMTextTable *b, OMDCompareContext *context)
{
    if ([a rowCount] != [b rowCount] || [a borderWidth] != [b borderWidth] ||
        ![[a columnEdges] isEqualToArray:[b columnEdges]] ||
        !OMDStringsEqual([a markdown], [b markdown]) ||
        !OMDColorsEqual([a borderColor], [b borderColor]) ||
        !OMDColorsEqual([a headerBackgroundColor], [b headerBackgroundColor]) ||
        !OMDColorsEqual([a bodyBackgroundColor], [b bodyBackgroundColor])) {
        return NO;
    }
    OMRenderedObject *objectA = [a renderedObject];
    OMRenderedObject *objectB = [b renderedObject];
    if (objectA == nil || objectB == nil) {
        return objectA == objectB;
    }
    return OMDRenderedObjectsEquivalent(objectA, objectB, context);
}

// Attachments are equivalent when their cells are equal (rules), show the
// same image at the same size (cached math and pictures are the same
// image), or, for a cell drawn from its source (diagrams, drawn tables),
// are the same size beside the same rendered object.
static BOOL OMDAttachmentsEquivalent(NSTextAttachment *a, NSTextAttachment *b, BOOL sameRenderedObject)
{
    if ([a class] != [b class]) {
        return NO;
    }
    id<NSTextAttachmentCell> cellA = [a attachmentCell];
    id<NSTextAttachmentCell> cellB = [b attachmentCell];
    if (cellA == nil || cellB == nil) {
        return cellA == cellB;
    }
    if ([(id)cellA class] != [(id)cellB class] || !NSEqualSizes([cellA cellSize], [cellB cellSize])) {
        return NO;
    }
    if ([(id)cellA isEqual:(id)cellB]) {
        return YES;
    }
    NSImage *imageA = [(id)cellA respondsToSelector:@selector(image)] ? [(id)cellA image] : nil;
    NSImage *imageB = [(id)cellB respondsToSelector:@selector(image)] ? [(id)cellB image] : nil;
    if (imageA != nil || imageB != nil) {
        return imageA == imageB;
    }
    return sameRenderedObject;
}

static BOOL OMDAttributeValuesEquivalent(id a, id b, BOOL sameRenderedObject, OMDCompareContext *context)
{
    if (a == b || [a isEqual:b]) {
        return YES;
    }
    if ([a isKindOfClass:[OMRenderedObject class]] && [b isKindOfClass:[OMRenderedObject class]]) {
        return OMDRenderedObjectsEquivalent(a, b, context);
    }
    if ([a isKindOfClass:[OMTextTable class]] && [b isKindOfClass:[OMTextTable class]]) {
        return OMDTextTablesEquivalent(a, b, context);
    }
    if ([a isKindOfClass:[NSTextAttachment class]] && [b isKindOfClass:[NSTextAttachment class]]) {
        return OMDAttachmentsEquivalent(a, b, sameRenderedObject);
    }
    return NO;
}

// Position updates are kept only if the whole run turns out equivalent.
static BOOL OMDAttributesEquivalent(NSDictionary *a, NSDictionary *b, NSString *ignoredKey, OMDCompareContext *context)
{
    if (a == b) {
        return YES;
    }
    NSUInteger countA = [a count] - ((ignoredKey != nil && [a objectForKey:ignoredKey] != nil) ? 1 : 0);
    NSUInteger countB = [b count] - ((ignoredKey != nil && [b objectForKey:ignoredKey] != nil) ? 1 : 0);
    if (countA != countB) {
        return NO;
    }
    NSMutableArray *updates = [NSMutableArray array];
    OMDCompareContext runContext = { context != NULL && context->ignorePositions, updates };
    OMRenderedObject *objectA = [a objectForKey:OMRenderedObjectAttributeName];
    OMRenderedObject *objectB = [b objectForKey:OMRenderedObjectAttributeName];
    BOOL sameRenderedObject = (objectA != nil && objectB != nil &&
                               OMDRenderedObjectsEquivalent(objectA, objectB, &runContext));
    [updates removeAllObjects];
    for (id key in a) {
        if (ignoredKey != nil && [key isEqual:ignoredKey]) {
            continue;
        }
        id valueB = [b objectForKey:key];
        if (valueB == nil || !OMDAttributeValuesEquivalent([a objectForKey:key], valueB, sameRenderedObject, &runContext)) {
            return NO;
        }
    }
    if (context != NULL && context->positionUpdates != nil) {
        [context->positionUpdates addObjectsFromArray:updates];
    }
    return YES;
}

// Whether index starts a paragraph of text.
static BOOL OMDStartsParagraph(NSString *text, NSUInteger index)
{
    return index == 0 || [text characterAtIndex:index - 1] == '\n';
}

// The paragraph styles at the starts of a paragraph in current and
// rendered match. A text storage gives every character of a paragraph the
// style of its first character when it fixes its attributes, so elsewhere
// paragraph styles are compared only through this.
static BOOL OMDParagraphStylesMatch(NSAttributedString *current,
                                    NSUInteger indexA,
                                    NSAttributedString *rendered,
                                    NSUInteger indexB)
{
    // A paragraph with no style gets the default one.
    id styleA = [current attribute:NSParagraphStyleAttributeName atIndex:indexA effectiveRange:NULL];
    id styleB = [rendered attribute:NSParagraphStyleAttributeName atIndex:indexB effectiveRange:NULL];
    if (styleA == nil) {
        styleA = [NSParagraphStyle defaultParagraphStyle];
    }
    if (styleB == nil) {
        styleB = [NSParagraphStyle defaultParagraphStyle];
    }
    return styleA == styleB || [styleA isEqual:styleB];
}

// How many leading characters the strings share.
static NSUInteger OMDCommonCharacterPrefix(NSString *a, NSString *b)
{
    NSUInteger limit = MIN([a length], [b length]);
    unichar bufferA[OMDCompareChunkLength];
    unichar bufferB[OMDCompareChunkLength];
    NSUInteger start = 0;
    while (start < limit) {
        NSUInteger length = MIN(OMDCompareChunkLength, limit - start);
        [a getCharacters:bufferA range:NSMakeRange(start, length)];
        [b getCharacters:bufferB range:NSMakeRange(start, length)];
        NSUInteger index = 0;
        for (; index < length; index++) {
            if (bufferA[index] != bufferB[index]) {
                return start + index;
            }
        }
        start += length;
    }
    return limit;
}

// How many trailing characters the strings share, at most limit.
static NSUInteger OMDCommonCharacterSuffix(NSString *a, NSString *b, NSUInteger limit)
{
    NSUInteger lengthA = [a length];
    NSUInteger lengthB = [b length];
    unichar bufferA[OMDCompareChunkLength];
    unichar bufferB[OMDCompareChunkLength];
    NSUInteger matched = 0;
    while (matched < limit) {
        NSUInteger length = MIN(OMDCompareChunkLength, limit - matched);
        [a getCharacters:bufferA range:NSMakeRange(lengthA - matched - length, length)];
        [b getCharacters:bufferB range:NSMakeRange(lengthB - matched - length, length)];
        NSUInteger index = 0;
        for (; index < length; index++) {
            if (bufferA[length - 1 - index] != bufferB[length - 1 - index]) {
                return matched + index;
            }
        }
        matched += length;
    }
    return limit;
}

// How many of the first limit characters have equivalent attributes.
static NSUInteger OMDEquivalentAttributePrefix(NSAttributedString *current,
                                               NSAttributedString *rendered,
                                               NSUInteger limit)
{
    NSString *text = [rendered string];
    NSUInteger index = 0;
    while (index < limit) {
        if (OMDStartsParagraph(text, index) && !OMDParagraphStylesMatch(current, index, rendered, index)) {
            return index;
        }
        NSRange rangeA = NSMakeRange(index, 1);
        NSRange rangeB = NSMakeRange(index, 1);
        NSDictionary *attributesA = [current attributesAtIndex:index effectiveRange:&rangeA];
        NSDictionary *attributesB = [rendered attributesAtIndex:index effectiveRange:&rangeB];
        if (!OMDAttributesEquivalent(attributesA, attributesB, NSParagraphStyleAttributeName, NULL)) {
            return index;
        }
        // Stop at the next paragraph, to check its style.
        NSUInteger end = MIN(MIN(NSMaxRange(rangeA), NSMaxRange(rangeB)), limit);
        NSRange newline = [text rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(index, end - index)];
        index = (newline.location != NSNotFound ? newline.location + 1 : end);
    }
    return limit;
}

// How many of the last limit characters have equivalent attributes, with
// rendered objects that only moved collected in context.
static NSUInteger OMDEquivalentAttributeSuffix(NSAttributedString *current,
                                               NSAttributedString *rendered,
                                               NSUInteger limit,
                                               OMDCompareContext *context)
{
    NSString *text = [rendered string];
    NSUInteger lengthA = [current length];
    NSUInteger lengthB = [rendered length];
    NSUInteger matched = 0;
    while (matched < limit) {
        NSUInteger indexA = lengthA - 1 - matched;
        NSUInteger indexB = lengthB - 1 - matched;
        NSRange rangeA = NSMakeRange(indexA, 1);
        NSRange rangeB = NSMakeRange(indexB, 1);
        NSDictionary *attributesA = [current attributesAtIndex:indexA effectiveRange:&rangeA];
        NSDictionary *attributesB = [rendered attributesAtIndex:indexB effectiveRange:&rangeB];
        if (!OMDAttributesEquivalent(attributesA, attributesB, NSParagraphStyleAttributeName, context)) {
            return matched;
        }
        NSUInteger step = MIN(MIN(indexA - rangeA.location, indexB - rangeB.location) + 1, limit - matched);
        // Stop at the start of this paragraph, to check its style.
        NSUInteger first = indexB + 1 - step;
        NSRange newline = [text rangeOfString:@"\n"
                                      options:(NSLiteralSearch | NSBackwardsSearch)
                                        range:NSMakeRange(first, indexB - first)];
        if (newline.location != NSNotFound) {
            first = newline.location + 1;
            step = indexB + 1 - first;
        }
        if (OMDStartsParagraph(text, first) &&
            !OMDParagraphStylesMatch(current, indexA + 1 - step, rendered, first)) {
            return matched;
        }
        matched += step;
    }
    return limit;
}

static BOOL OMDChangedRanges(NSAttributedString *current,
                             NSAttributedString *rendered,
                             NSRange *currentRangeOut,
                             NSRange *renderedRangeOut,
                             NSMutableArray *positionUpdates)
{
    NSString *currentText = [current string];
    NSString *renderedText = [rendered string];
    NSUInteger currentLength = [currentText length];
    NSUInteger renderedLength = [renderedText length];

    NSUInteger prefix = OMDCommonCharacterPrefix(currentText, renderedText);
    prefix = OMDEquivalentAttributePrefix(current, rendered, prefix);

    NSUInteger suffixLimit = MIN(currentLength, renderedLength) - prefix;
    NSUInteger suffix = OMDCommonCharacterSuffix(currentText, renderedText, suffixLimit);
    OMDCompareContext context = { YES, positionUpdates };
    suffix = OMDEquivalentAttributeSuffix(current, rendered, suffix, &context);
    // The kept text's first character may start a paragraph in one string
    // and not the other; then its paragraph's style must match too, or it
    // is replaced up to the next paragraph.
    while (suffix > 0) {
        NSUInteger firstA = currentLength - suffix;
        NSUInteger firstB = renderedLength - suffix;
        BOOL startsParagraph = OMDStartsParagraph(currentText, firstA) || OMDStartsParagraph(renderedText, firstB);
        if (!startsParagraph || OMDParagraphStylesMatch(current, firstA, rendered, firstB)) {
            break;
        }
        NSRange newline = [renderedText rangeOfString:@"\n"
                                              options:NSLiteralSearch
                                                range:NSMakeRange(firstB, renderedLength - firstB)];
        suffix = (newline.location != NSNotFound ? renderedLength - (newline.location + 1) : 0);
    }

    NSRange currentRange = NSMakeRange(prefix, currentLength - prefix - suffix);
    NSRange renderedRange = NSMakeRange(prefix, renderedLength - prefix - suffix);
    if (currentRangeOut != NULL) {
        *currentRangeOut = currentRange;
    }
    if (renderedRangeOut != NULL) {
        *renderedRangeOut = renderedRange;
    }
    return currentRange.length > 0 || renderedRange.length > 0 || [positionUpdates count] > 0;
}

BOOL OMDChangedRangesForRender(NSAttributedString *current,
                               NSAttributedString *rendered,
                               NSRange *currentRangeOut,
                               NSRange *renderedRangeOut)
{
    return OMDChangedRanges(current, rendered, currentRangeOut, renderedRangeOut, [NSMutableArray array]);
}

NSRange OMDApplyRenderedString(NSTextStorage *storage, NSAttributedString *rendered)
{
    if (storage == nil || rendered == nil) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSMutableArray *positionUpdates = [NSMutableArray array];
    NSRange currentRange = NSMakeRange(0, 0);
    NSRange renderedRange = NSMakeRange(0, 0);
    if (!OMDChangedRanges(storage, rendered, &currentRange, &renderedRange, positionUpdates)) {
        return NSMakeRange(NSNotFound, 0);
    }
    // Objects after the edit keep their text but take their new source
    // positions; changing them in place leaves the layout alone.
    NSUInteger index = 0;
    for (; index + 1 < [positionUpdates count]; index += 2) {
        [(OMRenderedObject *)[positionUpdates objectAtIndex:index]
            updateSourcePositionsFromObject:[positionUpdates objectAtIndex:index + 1]];
    }
    if (currentRange.length == 0 && renderedRange.length == 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    // The storage fixes the attributes of the new text itself (a paragraph's
    // closing newline takes the paragraph's style, for one), as it does for
    // a whole render; the comparisons above allow for that.
    [storage beginEditing];
    [storage replaceCharactersInRange:currentRange
                 withAttributedString:[rendered attributedSubstringFromRange:renderedRange]];
    [storage endEditing];
    return NSMakeRange(currentRange.location, renderedRange.length);
}
