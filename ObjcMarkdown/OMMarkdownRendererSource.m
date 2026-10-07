// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Mapping rendered output back to the Markdown source: rendered objects,
// block anchors and IDs, front matter and source lines.

#import "OMMarkdownRendererInternal.h"

// Kind, source and Markdown of an object while the document renders; the
// final pass turns it into an OMRenderedObject once block anchors are known.
static NSString * const OMPendingRenderedObjectAttributeName = @"OMPendingRenderedObject";
static NSString * const OMPendingObjectKindKey = @"kind";
static NSString * const OMPendingObjectSourceKey = @"source";
static NSString * const OMPendingObjectMarkdownKey = @"markdown";

// Tags the attachment characters appended to output since start.
void OMTagAppendedObject(NSMutableAttributedString *output,
                         NSUInteger start,
                         OMRenderedObjectKind kind,
                         NSString *source,
                         NSString *markdown)
{
    if (output == nil || start >= [output length] || source == nil) {
        return;
    }
    NSDictionary *pending = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithInteger:kind], OMPendingObjectKindKey,
                             source, OMPendingObjectSourceKey,
                             (markdown != nil ? markdown : source), OMPendingObjectMarkdownKey,
                             nil];
    NSString *text = [output string];
    NSUInteger index = start;
    for (; index < [output length]; index++) {
        if ([text characterAtIndex:index] == NSAttachmentCharacter &&
            [output attribute:NSAttachmentAttributeName atIndex:index effectiveRange:NULL] != nil) {
            [output addAttribute:OMPendingRenderedObjectAttributeName value:pending range:NSMakeRange(index, 1)];
        }
    }
}


// The node's raw source lines, joined with newlines.
NSString *OMSourceTextForNodeLines(cmark_node *node, const OMRenderContext *renderContext)
{
    NSArray *sourceLines = renderContext != NULL ? renderContext->sourceLines : nil;
    int firstLine = cmark_node_get_start_line(node);
    int lastLine = cmark_node_get_end_line(node);
    if (sourceLines == nil || firstLine < 1 || lastLine < firstLine || (NSUInteger)lastLine > [sourceLines count]) {
        return nil;
    }
    NSArray *lines = [sourceLines subarrayWithRange:NSMakeRange((NSUInteger)firstLine - 1,
                                                                (NSUInteger)(lastLine - firstLine + 1))];
    return [lines componentsJoinedByString:@"\n"];
}

NSString *OMImageMarkdownForNode(cmark_node *imageNode)
{
    const char *url = cmark_node_get_url(imageNode);
    const char *title = cmark_node_get_title(imageNode);
    NSString *urlString = url != NULL ? [NSString stringWithUTF8String:url] : @"";
    NSString *titleString = title != NULL ? [NSString stringWithUTF8String:title] : @"";
    NSMutableString *alt = [NSMutableString string];
    OMAppendInlineTextFromNode(imageNode, alt);
    if ([urlString rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound) {
        urlString = [NSString stringWithFormat:@"<%@>", urlString];
    }
    if ([titleString length] > 0) {
        return [NSString stringWithFormat:@"![%@](%@ \"%@\")", alt, urlString,
                [titleString stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    }
    return [NSString stringWithFormat:@"![%@](%@)", alt, urlString];
}

// The smallest block anchor containing location gives the object's source lines.
// The block anchors' target spans, sorted by start, for finding the
// innermost block at a location without scanning every anchor (#94).
typedef struct {
    NSUInteger start;
    NSUInteger length;
    NSUInteger startLine;
    NSUInteger endLine;
    NSUInteger order;
} OMAnchorSpan;

typedef struct {
    OMAnchorSpan *spans;
    NSUInteger count;
} OMAnchorIndex;

static int OMCompareAnchorSpans(const void *a, const void *b)
{
    const OMAnchorSpan *left = (const OMAnchorSpan *)a;
    const OMAnchorSpan *right = (const OMAnchorSpan *)b;
    if (left->start != right->start) {
        return left->start < right->start ? -1 : 1;
    }
    if (left->order != right->order) {
        return left->order < right->order ? -1 : 1;
    }
    return 0;
}

static OMAnchorIndex OMAnchorIndexMake(NSArray *blockAnchors)
{
    OMAnchorIndex index = { NULL, 0 };
    NSUInteger capacity = [blockAnchors count];
    if (capacity == 0) {
        return index;
    }
    index.spans = (OMAnchorSpan *)malloc(sizeof(OMAnchorSpan) * capacity);
    if (index.spans == NULL) {
        return index;
    }
    NSUInteger order = 0;
    for (NSDictionary *anchor in blockAnchors) {
        OMAnchorSpan span;
        span.order = order++;
        span.start = [[anchor objectForKey:OMMarkdownRendererAnchorTargetStartKey] unsignedIntegerValue];
        span.length = [[anchor objectForKey:OMMarkdownRendererAnchorTargetLengthKey] unsignedIntegerValue];
        span.startLine = [[anchor objectForKey:OMMarkdownRendererAnchorSourceStartLineKey] unsignedIntegerValue];
        span.endLine = [[anchor objectForKey:OMMarkdownRendererAnchorSourceEndLineKey] unsignedIntegerValue];
        if (span.length == 0 || span.startLine == 0 || span.endLine < span.startLine) {
            continue;
        }
        index.spans[index.count++] = span;
    }
    qsort(index.spans, index.count, sizeof(OMAnchorSpan), OMCompareAnchorSpans);
    return index;
}

static void OMAnchorIndexFree(OMAnchorIndex *index)
{
    free(index->spans);
    index->spans = NULL;
    index->count = 0;
}

// The source lines of the shortest anchor around location, the first in
// the anchors' order among equals. Anchors starting further back than the
// best length so far can't be as short, so the backwards scan stops there.
static NSRange OMSourceLineRangeForTargetLocation(const OMAnchorIndex *index, NSUInteger location)
{
    NSRange best = NSMakeRange(NSNotFound, 0);
    NSUInteger bestLength = NSUIntegerMax;
    NSUInteger bestOrder = NSUIntegerMax;
    NSUInteger low = 0;
    NSUInteger high = index->count;
    // The first anchor starting after location.
    while (low < high) {
        NSUInteger mid = low + (high - low) / 2;
        if (index->spans[mid].start <= location) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    while (low > 0) {
        const OMAnchorSpan *span = &index->spans[--low];
        if (location - span->start >= bestLength) {
            break;
        }
        if (location >= span->start + span->length || span->length > bestLength ||
            (span->length == bestLength && span->order > bestOrder)) {
            continue;
        }
        best = NSMakeRange(span->startLine, span->endLine - span->startLine + 1);
        bestLength = span->length;
        bestOrder = span->order;
    }
    return best;
}

// CommonMark drops a backslash before ASCII punctuation in text, so a formula
// from a cmark text node is compared with its source in that form too.
NSString *OMCommonMarkUnescaped(NSString *text)
{
    if ([text rangeOfString:@"\\"].location == NSNotFound) {
        return text;
    }
    NSMutableString *result = [NSMutableString stringWithCapacity:[text length]];
    NSUInteger length = [text length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [text characterAtIndex:index];
        if (ch == '\\' && index + 1 < length) {
            unichar next = [text characterAtIndex:index + 1];
            if (next < 128 && ispunct((int)next)) {
                [result appendFormat:@"%C", next];
                index += 2;
                continue;
            }
        }
        [result appendFormat:@"%C", ch];
        index += 1;
    }
    return result;
}

static BOOL OMMathSourceMatchesFormula(NSString *content, NSString *formula)
{
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *target = [formula stringByTrimmingCharactersInSet:space];
    return [[content stringByTrimmingCharactersInSet:space] isEqualToString:target] ||
           [[OMCommonMarkUnescaped(content) stringByTrimmingCharactersInSet:space] isEqualToString:target];
}

// The occurrence-th "$formula$" (or "$$formula$$") inside span, delimiters included.
static NSRange OMFindMathSource(NSString *markdown,
                                NSRange span,
                                NSString *formula,
                                BOOL display,
                                NSUInteger occurrence)
{
    NSUInteger end = NSMaxRange(span);
    NSUInteger delimiterLength = display ? 2 : 1;
    NSUInteger matches = 0;
    NSUInteger index = span.location;
    while (index < end) {
        unichar ch = [markdown characterAtIndex:index];
        if (ch == '\\') {
            index += 2;
            continue;
        }
        if (ch != '$') {
            index += 1;
            continue;
        }
        BOOL doubled = (index + 1 < end && [markdown characterAtIndex:index + 1] == '$');
        if (doubled != display) {
            index += doubled ? 2 : 1;
            continue;
        }
        NSUInteger contentStart = index + delimiterLength;
        NSUInteger close = contentStart;
        while (close < end) {
            unichar c = [markdown characterAtIndex:close];
            if (c == '\\') {
                close += 2;
                continue;
            }
            if (c == '$') {
                BOOL closeDoubled = (close + 1 < end && [markdown characterAtIndex:close + 1] == '$');
                if (closeDoubled == display) {
                    break;
                }
            }
            close += 1;
        }
        if (close >= end) {
            break;
        }
        NSString *content = [markdown substringWithRange:NSMakeRange(contentStart, close - contentStart)];
        if (OMMathSourceMatchesFormula(content, formula)) {
            if (matches == occurrence) {
                return NSMakeRange(index, close + delimiterLength - index);
            }
            matches += 1;
        }
        index = close + delimiterLength;
    }
    return NSMakeRange(NSNotFound, 0);
}

// The destination of the image syntax starting at index ("![alt](dest ...)"),
// and the syntax's full range; NSNotFound if it isn't an inline image.
static NSRange OMImageSyntaxRange(NSString *text, NSUInteger index, NSUInteger end, NSString **destination)
{
    NSRange notFound = NSMakeRange(NSNotFound, 0);
    if (index + 1 >= end || [text characterAtIndex:index] != '!' || [text characterAtIndex:index + 1] != '[') {
        return notFound;
    }
    NSRange bracket = [text rangeOfString:@"](" options:0 range:NSMakeRange(index, end - index)];
    if (bracket.location == NSNotFound) {
        return notFound;
    }
    NSUInteger cursor = NSMaxRange(bracket);
    NSUInteger destStart = cursor;
    NSUInteger destEnd = cursor;
    if (cursor < end && [text characterAtIndex:cursor] == '<') {
        NSRange close = [text rangeOfString:@">" options:0 range:NSMakeRange(cursor, end - cursor)];
        if (close.location == NSNotFound) {
            return notFound;
        }
        destStart = cursor + 1;
        destEnd = close.location;
        cursor = close.location + 1;
    } else {
        while (destEnd < end) {
            unichar c = [text characterAtIndex:destEnd];
            if (c == ')' || c == ' ' || c == '\t' || c == '\n') {
                break;
            }
            destEnd += 1;
        }
        cursor = destEnd;
    }
    NSRange closeParen = [text rangeOfString:@")" options:0 range:NSMakeRange(cursor, end - cursor)];
    if (closeParen.location == NSNotFound) {
        return notFound;
    }
    if (destination != NULL) {
        *destination = [text substringWithRange:NSMakeRange(destStart, destEnd - destStart)];
    }
    return NSMakeRange(index, NSMaxRange(closeParen) - index);
}

// The occurrence-th inline image in span whose destination matches the
// object's reconstructed Markdown.
static NSRange OMFindImageSource(NSString *markdown, NSRange span, NSString *imageMarkdown, NSUInteger occurrence)
{
    NSString *target = nil;
    if (OMImageSyntaxRange(imageMarkdown, 0, [imageMarkdown length], &target).location == NSNotFound || target == nil) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger end = NSMaxRange(span);
    NSUInteger matches = 0;
    NSUInteger index = span.location;
    while (index + 1 < end) {
        NSRange bang = [markdown rangeOfString:@"![" options:0 range:NSMakeRange(index, end - index)];
        if (bang.location == NSNotFound) {
            break;
        }
        NSString *destination = nil;
        NSRange syntax = OMImageSyntaxRange(markdown, bang.location, end, &destination);
        if (syntax.location != NSNotFound && [destination isEqualToString:target]) {
            if (matches == occurrence) {
                return syntax;
            }
            matches += 1;
        }
        index = bang.location + 2;
    }
    return NSMakeRange(NSNotFound, 0);
}

// Character span of 1-based source lines, without the final line break.
static NSRange OMCharacterSpanForLines(NSString *markdown, NSArray *lineStarts, NSRange lineRange)
{
    if (lineRange.location == NSNotFound || lineRange.location == 0 ||
        lineRange.location > [lineStarts count]) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger lastLine = NSMaxRange(lineRange) - 1;
    NSUInteger start = [[lineStarts objectAtIndex:lineRange.location - 1] unsignedIntegerValue];
    NSUInteger end = (lastLine < [lineStarts count])
        ? [[lineStarts objectAtIndex:lastLine] unsignedIntegerValue]
        : [markdown length];
    while (end > start && ([markdown characterAtIndex:end - 1] == '\n' || [markdown characterAtIndex:end - 1] == '\r')) {
        end -= 1;
    }
    return NSMakeRange(start, end - start);
}

static NSRange OMSourceRangeForPendingObject(NSString *markdown,
                                             NSRange span,
                                             OMRenderedObjectKind kind,
                                             NSString *source,
                                             NSUInteger occurrence)
{
    NSRange found = NSMakeRange(NSNotFound, 0);
    if (span.location == NSNotFound) {
        return found;
    }
    if (kind == OMRenderedObjectKindInlineMath || kind == OMRenderedObjectKindDisplayMath) {
        found = OMFindMathSource(markdown, span, source, kind == OMRenderedObjectKindDisplayMath, occurrence);
    } else if (kind == OMRenderedObjectKindImage) {
        found = OMFindImageSource(markdown, span, source, occurrence);
    }
    return found.location != NSNotFound ? found : span;
}

void OMResolvePendingRenderedObjects(NSMutableAttributedString *output,
                                     NSArray *blockAnchors,
                                     NSString *markdown)
{
    NSMutableArray *lineStarts = [NSMutableArray arrayWithObject:[NSNumber numberWithUnsignedInteger:0]];
    NSUInteger scan = 0;
    for (; scan < [markdown length]; scan++) {
        if ([markdown characterAtIndex:scan] == '\n') {
            [lineStarts addObject:[NSNumber numberWithUnsignedInteger:scan + 1]];
        }
    }
    // Repeats of the same object in one block resolve in document order.
    NSMutableDictionary *occurrences = [NSMutableDictionary dictionary];
    OMAnchorIndex anchorIndex = OMAnchorIndexMake(blockAnchors);

    NSUInteger index = 0;
    while (index < [output length]) {
        NSRange effective;
        NSDictionary *pending = [output attribute:OMPendingRenderedObjectAttributeName
                                          atIndex:index
                                   effectiveRange:&effective];
        if (pending != nil) {
            NSUInteger location = effective.location;
            for (; location < NSMaxRange(effective); location++) {
                OMRenderedObjectKind kind = (OMRenderedObjectKind)[[pending objectForKey:OMPendingObjectKindKey] integerValue];
                NSString *source = [pending objectForKey:OMPendingObjectSourceKey];
                NSRange lineRange = OMSourceLineRangeForTargetLocation(&anchorIndex, location);
                NSRange span = OMCharacterSpanForLines(markdown, lineStarts, lineRange);
                // Count repeats by what the search matches on: images by destination.
                NSString *matchText = source;
                if (kind == OMRenderedObjectKindImage) {
                    NSString *destination = nil;
                    OMImageSyntaxRange(source, 0, [source length], &destination);
                    matchText = destination != nil ? destination : source;
                }
                NSString *occurrenceKey = [NSString stringWithFormat:@"%lu|%ld|%@",
                                           (unsigned long)span.location, (long)kind, matchText];
                NSUInteger occurrence = [[occurrences objectForKey:occurrenceKey] unsignedIntegerValue];
                [occurrences setObject:[NSNumber numberWithUnsignedInteger:occurrence + 1] forKey:occurrenceKey];
                OMRenderedObject *object = [[OMRenderedObject alloc]
                    initWithKind:kind
                          source:source
                        markdown:[pending objectForKey:OMPendingObjectMarkdownKey]
                 sourceLineRange:lineRange
                     sourceRange:OMSourceRangeForPendingObject(markdown, span, kind, source, occurrence)];
                [output addAttribute:OMRenderedObjectAttributeName value:object range:NSMakeRange(location, 1)];
                [object release];
            }
            [output removeAttribute:OMPendingRenderedObjectAttributeName range:effective];
        }
        index = NSMaxRange(effective);
    }

    // Tables laid out as text: where each came from, for copying and revealing.
    index = 0;
    while (index < [output length]) {
        NSRange effective;
        OMTextTable *table = [output attribute:OMTextTableAttributeName atIndex:index effectiveRange:&effective];
        index = NSMaxRange(effective);
        if (table == nil || [table renderedObject] != nil || [table markdown] == nil) {
            continue;
        }
        NSRange lineRange = OMSourceLineRangeForTargetLocation(&anchorIndex, effective.location);
        NSRange span = OMCharacterSpanForLines(markdown, lineStarts, lineRange);
        OMRenderedObject *object = [[OMRenderedObject alloc]
            initWithKind:OMRenderedObjectKindTable
                  source:[table markdown]
                markdown:[table markdown]
         sourceLineRange:lineRange
             sourceRange:OMSourceRangeForPendingObject(markdown, span, OMRenderedObjectKindTable, [table markdown], 0)];
        [table setRenderedObject:object];
        [object release];
    }
    OMAnchorIndexFree(&anchorIndex);
}

static BOOL OMIsFrontMatterFence(NSString *line, BOOL closing)
{
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (closing && [trimmed isEqualToString:@"..."]) {
        return YES;
    }
    return [trimmed isEqualToString:@"---"] && [line hasPrefix:@"---"];
}

// Hides a leading YAML front matter block. Its lines become empty rather than
// removed, so cmark's line numbers still match the editor's.
NSString *OMMarkdownByBlankingFrontMatter(NSString *markdown)
{
    if (![markdown hasPrefix:@"---"]) {
        return markdown;
    }
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    if ([lines count] < 3 || !OMIsFrontMatterFence([lines objectAtIndex:0], NO)) {
        return markdown;
    }
    // Require YAML-looking content ("key:") so a leading thematic break
    // followed by a setext heading is not mistaken for metadata.
    NSString *firstContent = [[lines objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSRange colon = [firstContent rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0 ||
        [firstContent rangeOfString:@" "].location < colon.location) {
        return markdown;
    }
    NSUInteger closingIndex = 1;
    for (; closingIndex < [lines count]; closingIndex++) {
        if (OMIsFrontMatterFence([lines objectAtIndex:closingIndex], YES)) {
            break;
        }
    }
    if (closingIndex >= [lines count]) {
        return markdown;
    }
    NSMutableArray *blanked = [[lines mutableCopy] autorelease];
    NSUInteger index = 0;
    for (; index <= closingIndex; index++) {
        [blanked replaceObjectAtIndex:index withObject:@""];
    }
    return [blanked componentsJoinedByString:@"\n"];
}

NSArray *OMSourceLinesForMarkdown(NSString *markdown)
{
    NSMutableArray *lines = [NSMutableArray array];
    if (markdown == nil || [markdown length] == 0) {
        return lines;
    }

    NSUInteger totalLength = [markdown length];
    NSUInteger cursor = 0;
    while (cursor < totalLength) {
        NSRange lineRange = [markdown lineRangeForRange:NSMakeRange(cursor, 0)];
        NSUInteger lineStart = lineRange.location;
        NSUInteger contentLength = lineRange.length;

        while (contentLength > 0) {
            unichar ch = [markdown characterAtIndex:lineStart + contentLength - 1];
            if (ch == '\n' || ch == '\r') {
                contentLength -= 1;
                continue;
            }
            break;
        }

        NSString *line = [markdown substringWithRange:NSMakeRange(lineStart, contentLength)];
        [lines addObject:line];
        cursor = NSMaxRange(lineRange);
    }
    return lines;
}

BOOL OMNodeLineBounds(cmark_node *node, NSUInteger *startLineOut, NSUInteger *endLineOut)
{
    if (node == NULL) {
        return NO;
    }

    int startLine = cmark_node_get_start_line(node);
    int endLine = cmark_node_get_end_line(node);
    if (startLine <= 0) {
        return NO;
    }
    if (endLine < startLine) {
        endLine = startLine;
    }

    if (startLineOut != NULL) {
        *startLineOut = (NSUInteger)startLine;
    }
    if (endLineOut != NULL) {
        *endLineOut = (NSUInteger)endLine;
    }
    return YES;
}

NSString *OMSourceFragmentForNode(cmark_node *node, NSArray *sourceLines)
{
    if (node == NULL || sourceLines == nil) {
        return nil;
    }

    NSUInteger startLine = 0;
    NSUInteger endLine = 0;
    if (!OMNodeLineBounds(node, &startLine, &endLine)) {
        return nil;
    }

    int startColumnValue = cmark_node_get_start_column(node);
    int endColumnValue = cmark_node_get_end_column(node);
    if (startColumnValue <= 0 || endColumnValue <= 0) {
        return nil;
    }

    NSUInteger lineCount = [sourceLines count];
    if (startLine == 0 || startLine > lineCount) {
        return nil;
    }
    if (endLine < startLine) {
        endLine = startLine;
    }
    if (endLine > lineCount) {
        endLine = lineCount;
    }

    NSMutableString *fragment = [NSMutableString string];
    NSUInteger line = startLine;
    for (; line <= endLine; line++) {
        NSString *sourceLine = [sourceLines objectAtIndex:line - 1];
        NSUInteger lineLength = [sourceLine length];
        NSUInteger lineStartColumn = (line == startLine) ? (NSUInteger)startColumnValue : 1;
        NSUInteger lineEndColumn = (line == endLine) ? (NSUInteger)endColumnValue : lineLength;

        if (lineStartColumn == 0 || lineStartColumn > lineLength + 1) {
            return nil;
        }
        if (lineEndColumn > lineLength) {
            lineEndColumn = lineLength;
        }

        if (lineStartColumn <= lineEndColumn && lineLength > 0) {
            NSRange range = NSMakeRange(lineStartColumn - 1,
                                        lineEndColumn - lineStartColumn + 1);
            [fragment appendString:[sourceLine substringWithRange:range]];
        }

        if (line < endLine) {
            [fragment appendString:@"\n"];
        }
    }

    return fragment;
}

static NSString *OMStableBlockIDForTypeAndLineRange(cmark_node_type nodeType,
                                                    NSUInteger startLine,
                                                    NSUInteger endLine,
                                                    const OMRenderContext *renderContext)
{
    OMBlockSignatureIndex *signatures = renderContext != NULL ? renderContext->blockSignatures : nil;
    if (signatures == nil) {
        return nil;
    }
    return [signatures blockIDForNodeType:(int)nodeType startLine:startLine endLine:endLine];
}

void OMRecordBlockAnchorForSourceRange(cmark_node *node,
                                       NSUInteger sourceStartLine,
                                       NSUInteger sourceEndLine,
                                       NSUInteger targetStart,
                                       NSUInteger targetEnd,
                                       const OMRenderContext *renderContext)
{
    NSMutableArray *blockAnchors = renderContext != NULL ? renderContext->blockAnchors : nil;
    if (blockAnchors == nil || node == NULL) {
        return;
    }
    if (sourceStartLine == 0 || sourceEndLine < sourceStartLine) {
        return;
    }
    if (targetEnd <= targetStart) {
        return;
    }

    NSMutableDictionary *anchor = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithUnsignedInteger:sourceStartLine], OMMarkdownRendererAnchorSourceStartLineKey,
                                   [NSNumber numberWithUnsignedInteger:sourceEndLine], OMMarkdownRendererAnchorSourceEndLineKey,
                                   [NSNumber numberWithUnsignedInteger:targetStart], OMMarkdownRendererAnchorTargetStartKey,
                                   [NSNumber numberWithUnsignedInteger:(targetEnd - targetStart)], OMMarkdownRendererAnchorTargetLengthKey,
                                   nil];
    NSString *blockID = OMStableBlockIDForTypeAndLineRange(cmark_node_get_type(node),
                                                           sourceStartLine,
                                                           sourceEndLine,
                                                           renderContext);
    if (blockID != nil && [blockID length] > 0) {
        [anchor setObject:blockID forKey:OMMarkdownRendererAnchorBlockIDKey];
    }
    [blockAnchors addObject:anchor];
}

void OMRecordBlockAnchor(cmark_node *node,
                         NSUInteger targetStart,
                         NSUInteger targetEnd,
                         const OMRenderContext *renderContext)
{
    NSUInteger sourceStartLine = 0;
    NSUInteger sourceEndLine = 0;
    if (!OMNodeLineBounds(node, &sourceStartLine, &sourceEndLine)) {
        return;
    }
    OMRecordBlockAnchorForSourceRange(node,
                                      sourceStartLine,
                                      sourceEndLine,
                                      targetStart,
                                      targetEnd,
                                      renderContext);
}
