// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareSelection.h"
#import "OMMarkdownRenderer.h"

NSString *OMDShareDedentedLines(NSArray *lines)
{
    NSUInteger indent = NSNotFound;
    for (NSString *line in lines) {
        NSUInteger length = [line length];
        NSUInteger index = 0;
        while (index < length && [line characterAtIndex:index] == ' ') {
            index++;
        }
        if (index < length && index < indent) {
            indent = index;
        }
    }
    if (indent == NSNotFound || indent == 0) {
        return [lines componentsJoinedByString:@"\n"];
    }
    NSMutableArray *dedented = [NSMutableArray arrayWithCapacity:[lines count]];
    for (NSString *line in lines) {
        [dedented addObject:([line length] >= indent ? [line substringFromIndex:indent] : @"")];
    }
    return [dedented componentsJoinedByString:@"\n"];
}

NSRange OMDSourceLineRangeForPreviewRange(NSRange range, NSArray *blockAnchors)
{
    if (range.location == NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
    }
    // The anchors the range overlaps (an empty range: the one it's in).
    NSMutableArray *touched = [NSMutableArray array];
    for (NSDictionary *anchor in blockAnchors) {
        NSUInteger start = [[anchor objectForKey:OMMarkdownRendererAnchorTargetStartKey] unsignedIntegerValue];
        NSUInteger length = [[anchor objectForKey:OMMarkdownRendererAnchorTargetLengthKey] unsignedIntegerValue];
        BOOL overlaps = (range.length > 0)
            ? (range.location < start + length && start < NSMaxRange(range))
            : (range.location >= start && range.location < start + length);
        if (overlaps) {
            [touched addObject:anchor];
        }
    }
    // A click between blocks: the blocks that end last before it.
    if ([touched count] == 0 && range.length == 0) {
        NSUInteger lastEnd = 0;
        for (NSDictionary *anchor in blockAnchors) {
            NSUInteger end = [[anchor objectForKey:OMMarkdownRendererAnchorTargetStartKey] unsignedIntegerValue] +
                             [[anchor objectForKey:OMMarkdownRendererAnchorTargetLengthKey] unsignedIntegerValue];
            if (end <= range.location && end > lastEnd) {
                lastEnd = end;
            }
        }
        for (NSDictionary *anchor in blockAnchors) {
            NSUInteger end = [[anchor objectForKey:OMMarkdownRendererAnchorTargetStartKey] unsignedIntegerValue] +
                             [[anchor objectForKey:OMMarkdownRendererAnchorTargetLengthKey] unsignedIntegerValue];
            if (lastEnd > 0 && end == lastEnd) {
                [touched addObject:anchor];
            }
        }
    }
    // Only the innermost: a list's anchor holds its items', and selecting
    // one item shouldn't share the whole list.
    NSUInteger first = NSNotFound;
    NSUInteger last = 0;
    for (NSDictionary *anchor in touched) {
        NSUInteger startLine = [[anchor objectForKey:OMMarkdownRendererAnchorSourceStartLineKey] unsignedIntegerValue];
        NSUInteger endLine = [[anchor objectForKey:OMMarkdownRendererAnchorSourceEndLineKey] unsignedIntegerValue];
        BOOL holdsAnother = NO;
        for (NSDictionary *other in touched) {
            if (other == anchor) {
                continue;
            }
            NSUInteger otherStart = [[other objectForKey:OMMarkdownRendererAnchorSourceStartLineKey] unsignedIntegerValue];
            NSUInteger otherEnd = [[other objectForKey:OMMarkdownRendererAnchorSourceEndLineKey] unsignedIntegerValue];
            BOOL inside = (otherStart >= startLine && otherEnd <= endLine);
            BOOL same = (otherStart == startLine && otherEnd == endLine);
            if (inside && !same) {
                holdsAnother = YES;
                break;
            }
        }
        if (holdsAnother) {
            continue;
        }
        first = MIN(first, startLine);
        last = MAX(last, endLine);
    }
    if (first == NSNotFound || first == 0 || last < first) {
        return NSMakeRange(NSNotFound, 0);
    }
    return NSMakeRange(first, last - first + 1);
}

NSString *OMDShareMarkdownForPreviewRange(NSString *markdown, NSRange range, NSArray *blockAnchors)
{
    if (markdown == nil) {
        return nil;
    }
    NSRange lineRange = OMDSourceLineRangeForPreviewRange(range, blockAnchors);
    if (lineRange.location == NSNotFound) {
        return nil;
    }
    NSUInteger first = lineRange.location;
    NSUInteger last = NSMaxRange(lineRange) - 1;
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    if (first > [lines count]) {
        return nil;
    }
    last = MIN(last, [lines count]);
    NSMutableArray *selected = [NSMutableArray array];
    for (NSString *line in [lines subarrayWithRange:NSMakeRange(first - 1, last - first + 1)]) {
        [selected addObject:([line hasSuffix:@"\r"] ? [line substringToIndex:[line length] - 1] : line)];
    }
    return OMDShareDedentedLines(selected);
}
