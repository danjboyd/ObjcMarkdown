// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDPreviewSync.h"

#include <cmark.h>
#include <float.h>
#include <math.h>

typedef NS_ENUM(NSUInteger, OMDAnchorLineFamily) {
    OMDAnchorLineFamilyBlank = 0,
    OMDAnchorLineFamilyText = 1,
    OMDAnchorLineFamilyList = 2,
    OMDAnchorLineFamilyCode = 3,
    OMDAnchorLineFamilyRule = 4
};

static NSString * const OMDLineStartKey = @"start";
static NSString * const OMDLineLengthKey = @"length";
static NSString * const OMDLineTokensKey = @"tokens";
static NSString * const OMDLineNormalizedKey = @"normalized";
static NSString * const OMDLineFamilyKey = @"family";
static NSString * const OMDAnchorSourceStartLineKey = @"sourceStartLine";
static NSString * const OMDAnchorSourceEndLineKey = @"sourceEndLine";
static NSString * const OMDAnchorTargetStartKey = @"targetStart";
static NSString * const OMDAnchorTargetLengthKey = @"targetLength";
static NSString * const OMDAnchorBlockIDKey = @"blockID";

static NSString *OMDCachedSourceDescriptorText = nil;
static NSArray *OMDCachedSourceDescriptors = nil;

static NSString *OMDTrimLeadingWhitespace(NSString *line)
{
    if (line == nil || [line length] == 0) {
        return @"";
    }

    NSUInteger length = [line length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [line characterAtIndex:index];
        if (ch == ' ' || ch == '\t') {
            index += 1;
            continue;
        }
        break;
    }
    return (index > 0) ? [line substringFromIndex:index] : line;
}

static NSString *OMDNormalizeAnchorLine(NSString *line)
{
    if (line == nil || [line length] == 0) {
        return @"";
    }

    NSMutableString *normalized = [NSMutableString stringWithCapacity:[line length]];
    NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];
    BOOL previousWasSpace = YES;
    NSUInteger length = [line length];

    NSUInteger i = 0;
    for (; i < length; i++) {
        unichar ch = [line characterAtIndex:i];
        if ([alphanumeric characterIsMember:ch]) {
            NSString *s = [[NSString stringWithCharacters:&ch length:1] lowercaseString];
            [normalized appendString:s];
            previousWasSpace = NO;
        } else if (!previousWasSpace) {
            [normalized appendString:@" "];
            previousWasSpace = YES;
        }
    }

    while ([normalized hasSuffix:@" "]) {
        [normalized deleteCharactersInRange:NSMakeRange([normalized length] - 1, 1)];
    }
    return normalized;
}

static NSArray *OMDAnchorTokensForNormalizedLine(NSString *normalized)
{
    if (normalized == nil || [normalized length] == 0) {
        return [NSArray array];
    }

    NSArray *components = [normalized componentsSeparatedByString:@" "];
    NSMutableArray *tokens = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];

    for (NSString *token in components) {
        if ([token length] < 2 || [seen containsObject:token]) {
            continue;
        }
        [tokens addObject:token];
        [seen addObject:token];
        if ([tokens count] >= 8) {
            break;
        }
    }
    return tokens;
}

static BOOL OMDHasOrderedListMarker(NSString *trimmed, NSUInteger *markerLengthOut)
{
    if (trimmed == nil || [trimmed length] == 0) {
        return NO;
    }

    NSUInteger length = [trimmed length];
    NSUInteger index = 0;
    while (index < length) {
        unichar ch = [trimmed characterAtIndex:index];
        if (ch >= '0' && ch <= '9') {
            index += 1;
            continue;
        }
        break;
    }
    if (index == 0 || index >= length) {
        return NO;
    }

    unichar marker = [trimmed characterAtIndex:index];
    if (marker != '.' && marker != ')') {
        return NO;
    }
    index += 1;
    if (index < length) {
        unichar spacing = [trimmed characterAtIndex:index];
        if (spacing == ' ' || spacing == '\t') {
            index += 1;
        }
    }

    if (markerLengthOut != NULL) {
        *markerLengthOut = index;
    }
    return YES;
}

static BOOL OMDIsHorizontalRuleLine(NSString *trimmed)
{
    if (trimmed == nil || [trimmed length] == 0) {
        return NO;
    }

    unichar marker = 0;
    NSUInteger markerCount = 0;
    NSUInteger length = [trimmed length];
    NSUInteger i = 0;
    for (; i < length; i++) {
        unichar ch = [trimmed characterAtIndex:i];
        if (ch == ' ' || ch == '\t') {
            continue;
        }
        if (ch != '-' && ch != '*' && ch != '_') {
            return NO;
        }
        if (marker == 0) {
            marker = ch;
        } else if (marker != ch) {
            return NO;
        }
        markerCount += 1;
    }

    return markerCount >= 3;
}

static BOOL OMDLineStartsWithFence(NSString *trimmed)
{
    return [trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"];
}

static BOOL OMDLineHasBulletMarker(NSString *trimmed, NSUInteger *markerLengthOut)
{
    if (trimmed == nil || [trimmed length] < 2) {
        return NO;
    }

    unichar marker = [trimmed characterAtIndex:0];
    if (marker != '-' && marker != '+' && marker != '*') {
        return NO;
    }

    unichar spacing = [trimmed characterAtIndex:1];
    if (spacing != ' ' && spacing != '\t') {
        return NO;
    }

    if (markerLengthOut != NULL) {
        *markerLengthOut = 2;
    }
    return YES;
}

static NSString *OMDStripMarkdownDecorations(NSString *line,
                                             OMDAnchorLineFamily *familyOut,
                                             BOOL *insideFence)
{
    NSString *trimmed = OMDTrimLeadingWhitespace(line);
    if (trimmed == nil || [trimmed length] == 0) {
        if (familyOut != NULL) {
            *familyOut = OMDAnchorLineFamilyBlank;
        }
        return @"";
    }

    if (insideFence != NULL && *insideFence) {
        if (OMDLineStartsWithFence(trimmed)) {
            *insideFence = NO;
            if (familyOut != NULL) {
                *familyOut = OMDAnchorLineFamilyCode;
            }
            return @"";
        }
        if (familyOut != NULL) {
            *familyOut = OMDAnchorLineFamilyCode;
        }
        return trimmed;
    }

    if (OMDLineStartsWithFence(trimmed)) {
        if (insideFence != NULL) {
            *insideFence = YES;
        }
        if (familyOut != NULL) {
            *familyOut = OMDAnchorLineFamilyCode;
        }
        return @"";
    }

    if (OMDIsHorizontalRuleLine(trimmed)) {
        if (familyOut != NULL) {
            *familyOut = OMDAnchorLineFamilyRule;
        }
        return @"rule";
    }

    NSUInteger headingLevel = 0;
    NSUInteger length = [trimmed length];
    while (headingLevel < length && headingLevel < 6 && [trimmed characterAtIndex:headingLevel] == '#') {
        headingLevel += 1;
    }
    if (headingLevel > 0 && headingLevel < length) {
        unichar separator = [trimmed characterAtIndex:headingLevel];
        if (separator == ' ' || separator == '\t') {
            if (familyOut != NULL) {
                *familyOut = OMDAnchorLineFamilyText;
            }
            NSString *headingText = [trimmed substringFromIndex:headingLevel + 1];
            return OMDTrimLeadingWhitespace(headingText);
        }
    }

    NSString *unquoted = trimmed;
    BOOL strippedQuote = NO;
    while ([unquoted hasPrefix:@">"]) {
        strippedQuote = YES;
        if ([unquoted length] == 1) {
            unquoted = @"";
            break;
        }
        unquoted = OMDTrimLeadingWhitespace([unquoted substringFromIndex:1]);
    }
    if (strippedQuote) {
        trimmed = unquoted;
    }

    NSUInteger markerLength = 0;
    if (OMDLineHasBulletMarker(trimmed, &markerLength)) {
        if (familyOut != NULL) {
            *familyOut = OMDAnchorLineFamilyList;
        }
        return OMDTrimLeadingWhitespace([trimmed substringFromIndex:markerLength]);
    }
    if (OMDHasOrderedListMarker(trimmed, &markerLength)) {
        if (familyOut != NULL) {
            *familyOut = OMDAnchorLineFamilyList;
        }
        return OMDTrimLeadingWhitespace([trimmed substringFromIndex:markerLength]);
    }

    if ([line hasPrefix:@"    "] || [line hasPrefix:@"\t"]) {
        if (familyOut != NULL) {
            *familyOut = OMDAnchorLineFamilyCode;
        }
        if ([line hasPrefix:@"\t"]) {
            return [line substringFromIndex:1];
        }
        return [line substringFromIndex:4];
    }

    if (familyOut != NULL) {
        *familyOut = OMDAnchorLineFamilyText;
    }
    return trimmed;
}

static OMDAnchorLineFamily OMDRenderedLineFamilyForLine(NSString *line)
{
    NSString *trimmed = OMDTrimLeadingWhitespace(line);
    if (trimmed == nil || [trimmed length] == 0) {
        return OMDAnchorLineFamilyBlank;
    }
    if (OMDIsHorizontalRuleLine(trimmed)) {
        return OMDAnchorLineFamilyRule;
    }
    if (OMDLineHasBulletMarker(trimmed, NULL) || OMDHasOrderedListMarker(trimmed, NULL)) {
        return OMDAnchorLineFamilyList;
    }
    return OMDAnchorLineFamilyText;
}

static NSArray *OMDLineInfosForText(NSString *text, BOOL markdownSource)
{
    NSMutableArray *infos = [NSMutableArray array];
    NSUInteger totalLength = [text length];
    if (totalLength == 0) {
        NSDictionary *empty = [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithUnsignedInteger:0], OMDLineStartKey,
                               [NSNumber numberWithUnsignedInteger:0], OMDLineLengthKey,
                               [NSArray array], OMDLineTokensKey,
                               @"", OMDLineNormalizedKey,
                               [NSNumber numberWithUnsignedInteger:OMDAnchorLineFamilyBlank], OMDLineFamilyKey,
                               nil];
        [infos addObject:empty];
        return infos;
    }

    NSUInteger cursor = 0;
    BOOL insideFence = NO;
    while (cursor < totalLength) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(cursor, 0)];
        NSUInteger lineStart = lineRange.location;
        NSUInteger contentLength = lineRange.length;

        while (contentLength > 0) {
            unichar ch = [text characterAtIndex:lineStart + contentLength - 1];
            if (ch == '\n' || ch == '\r') {
                contentLength -= 1;
                continue;
            }
            break;
        }

        NSString *line = [text substringWithRange:NSMakeRange(lineStart, contentLength)];
        OMDAnchorLineFamily family = OMDAnchorLineFamilyText;
        NSString *anchorText = nil;
        if (markdownSource) {
            anchorText = OMDStripMarkdownDecorations(line, &family, &insideFence);
        } else {
            family = OMDRenderedLineFamilyForLine(line);
            anchorText = line;
        }

        NSString *normalized = OMDNormalizeAnchorLine(anchorText);
        NSArray *tokens = OMDAnchorTokensForNormalizedLine(normalized);
        NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithUnsignedInteger:lineStart], OMDLineStartKey,
                              [NSNumber numberWithUnsignedInteger:contentLength], OMDLineLengthKey,
                              tokens, OMDLineTokensKey,
                              normalized, OMDLineNormalizedKey,
                              [NSNumber numberWithUnsignedInteger:family], OMDLineFamilyKey,
                              nil];
        [infos addObject:info];
        cursor = NSMaxRange(lineRange);
    }

    return infos;
}

static NSUInteger OMDLineInfoStart(NSDictionary *lineInfo)
{
    NSNumber *number = [lineInfo objectForKey:OMDLineStartKey];
    return number != nil ? [number unsignedIntegerValue] : 0;
}

static NSUInteger OMDLineInfoLength(NSDictionary *lineInfo)
{
    NSNumber *number = [lineInfo objectForKey:OMDLineLengthKey];
    return number != nil ? [number unsignedIntegerValue] : 0;
}

static NSArray *OMDLineInfoTokens(NSDictionary *lineInfo)
{
    NSArray *tokens = [lineInfo objectForKey:OMDLineTokensKey];
    return tokens != nil ? tokens : [NSArray array];
}

static NSString *OMDLineInfoNormalized(NSDictionary *lineInfo)
{
    NSString *normalized = [lineInfo objectForKey:OMDLineNormalizedKey];
    return normalized != nil ? normalized : @"";
}

static OMDAnchorLineFamily OMDLineInfoFamily(NSDictionary *lineInfo)
{
    NSNumber *number = [lineInfo objectForKey:OMDLineFamilyKey];
    return number != nil ? (OMDAnchorLineFamily)[number unsignedIntegerValue] : OMDAnchorLineFamilyText;
}

static NSUInteger OMDLineIndexForLocation(NSArray *lineInfos, NSUInteger location)
{
    NSUInteger count = [lineInfos count];
    if (count == 0) {
        return NSNotFound;
    }

    NSUInteger i = 0;
    for (; i < count; i++) {
        NSDictionary *lineInfo = [lineInfos objectAtIndex:i];
        NSUInteger start = OMDLineInfoStart(lineInfo);
        NSUInteger length = OMDLineInfoLength(lineInfo);
        NSUInteger end = start + length;
        if (location <= end) {
            return i;
        }
    }
    return count - 1;
}

static BOOL OMDLineFamiliesCompatible(OMDAnchorLineFamily left, OMDAnchorLineFamily right)
{
    if (left == right) {
        return YES;
    }
    if ((left == OMDAnchorLineFamilyText && right == OMDAnchorLineFamilyList) ||
        (left == OMDAnchorLineFamilyList && right == OMDAnchorLineFamilyText)) {
        return YES;
    }
    return NO;
}

static void OMDAppendUniqueTokens(NSMutableArray *destination, NSArray *source, NSUInteger maxCount)
{
    if (destination == nil || source == nil || maxCount == 0) {
        return;
    }

    NSMutableSet *seen = [NSMutableSet setWithArray:destination];
    for (NSString *token in source) {
        if ([token length] == 0 || [seen containsObject:token]) {
            continue;
        }
        [destination addObject:token];
        [seen addObject:token];
        if ([destination count] >= maxCount) {
            break;
        }
    }
}

static NSArray *OMDContextTokensForSourceLine(NSArray *sourceInfos,
                                              NSUInteger sourceIndex,
                                              OMDAnchorLineFamily sourceFamily)
{
    if ([sourceInfos count] == 0 || sourceIndex >= [sourceInfos count]) {
        return [NSArray array];
    }

    NSMutableArray *tokens = [NSMutableArray array];
    NSDictionary *center = [sourceInfos objectAtIndex:sourceIndex];
    OMDAppendUniqueTokens(tokens, OMDLineInfoTokens(center), 14);

    NSInteger radius = 1;
    while ([tokens count] < 14 && radius <= 3) {
        NSInteger left = (NSInteger)sourceIndex - radius;
        NSInteger right = (NSInteger)sourceIndex + radius;

        if (left >= 0) {
            NSDictionary *lineInfo = [sourceInfos objectAtIndex:(NSUInteger)left];
            if (OMDLineFamiliesCompatible(sourceFamily, OMDLineInfoFamily(lineInfo))) {
                OMDAppendUniqueTokens(tokens, OMDLineInfoTokens(lineInfo), 14);
            }
        }
        if (right < (NSInteger)[sourceInfos count]) {
            NSDictionary *lineInfo = [sourceInfos objectAtIndex:(NSUInteger)right];
            if (OMDLineFamiliesCompatible(sourceFamily, OMDLineInfoFamily(lineInfo))) {
                OMDAppendUniqueTokens(tokens, OMDLineInfoTokens(lineInfo), 14);
            }
        }
        radius += 1;
    }

    return tokens;
}

static double OMDTokenOverlapScore(NSArray *anchorTokens, NSArray *candidateTokens)
{
    NSUInteger anchorCount = [anchorTokens count];
    NSUInteger candidateCount = [candidateTokens count];
    if (anchorCount == 0 || candidateCount == 0) {
        return 0.0;
    }

    NSUInteger matches = 0;
    for (NSString *token in anchorTokens) {
        if ([candidateTokens containsObject:token]) {
            matches += 1;
        }
    }
    if (matches == 0) {
        return 0.0;
    }

    double recall = (double)matches / (double)anchorCount;
    double precision = (double)matches / (double)candidateCount;
    return (recall * 70.0) + (precision * 30.0);
}

static double OMDNormalizedLineBonus(NSString *anchorNormalized, NSString *candidateNormalized)
{
    if ([anchorNormalized length] == 0 || [candidateNormalized length] == 0) {
        return 0.0;
    }
    if ([anchorNormalized isEqualToString:candidateNormalized]) {
        return 35.0;
    }
    if ([candidateNormalized rangeOfString:anchorNormalized].location != NSNotFound ||
        [anchorNormalized rangeOfString:candidateNormalized].location != NSNotFound) {
        return 16.0;
    }
    return 0.0;
}

static NSUInteger OMDSelectBestTargetLine(NSArray *targetInfos,
                                          NSArray *anchorTokens,
                                          NSString *anchorNormalized,
                                          OMDAnchorLineFamily sourceFamily,
                                          NSUInteger expectedLineIndex)
{
    NSUInteger count = [targetInfos count];
    if (count == 0) {
        return NSNotFound;
    }

    double bestScore = -DBL_MAX;
    NSUInteger bestIndex = expectedLineIndex < count ? expectedLineIndex : 0;

    NSUInteger i = 0;
    for (; i < count; i++) {
        NSDictionary *candidate = [targetInfos objectAtIndex:i];
        NSArray *candidateTokens = OMDLineInfoTokens(candidate);
        NSString *candidateNormalized = OMDLineInfoNormalized(candidate);
        OMDAnchorLineFamily candidateFamily = OMDLineInfoFamily(candidate);

        double score = OMDTokenOverlapScore(anchorTokens, candidateTokens);
        score += OMDNormalizedLineBonus(anchorNormalized, candidateNormalized);

        if (sourceFamily == candidateFamily) {
            score += 18.0;
        } else if (OMDLineFamiliesCompatible(sourceFamily, candidateFamily)) {
            score += 8.0;
        } else if (sourceFamily == OMDAnchorLineFamilyCode && candidateFamily == OMDAnchorLineFamilyText) {
            score += 4.0;
        }

        NSInteger distance = (NSInteger)i - (NSInteger)expectedLineIndex;
        score -= fabs((double)distance) * 1.2;

        if (score > bestScore) {
            bestScore = score;
            bestIndex = i;
        }
    }

    if (bestScore < 1.0) {
        return NSNotFound;
    }
    return bestIndex;
}

static NSUInteger OMDLocationUsingLineAndColumnRatio(NSDictionary *sourceInfo,
                                                     NSUInteger sourceLocation,
                                                     NSDictionary *targetInfo,
                                                     NSUInteger targetTextLength)
{
    NSUInteger sourceStart = OMDLineInfoStart(sourceInfo);
    NSUInteger sourceLength = OMDLineInfoLength(sourceInfo);
    NSUInteger targetStart = OMDLineInfoStart(targetInfo);
    NSUInteger targetLength = OMDLineInfoLength(targetInfo);

    double columnRatio = 0.0;
    if (sourceLength > 0) {
        NSUInteger sourceColumn = sourceLocation > sourceStart ? (sourceLocation - sourceStart) : 0;
        if (sourceColumn > sourceLength) {
            sourceColumn = sourceLength;
        }
        columnRatio = (double)sourceColumn / (double)sourceLength;
    }

    NSUInteger mapped = targetStart;
    if (targetLength > 0) {
        NSUInteger column = (NSUInteger) llround(columnRatio * (double)targetLength);
        if (column >= targetLength) {
            column = targetLength - 1;
        }
        mapped = targetStart + column;
    }

    if (targetTextLength == 0) {
        return 0;
    }
    if (mapped >= targetTextLength) {
        return targetTextLength - 1;
    }
    return mapped;
}

static NSUInteger OMDBestMatchLocationInText(NSString *targetText,
                                             NSArray *tokens,
                                             NSUInteger expectedLocation)
{
    if (targetText == nil || [targetText length] == 0 || [tokens count] == 0) {
        return expectedLocation;
    }

    NSUInteger targetLength = [targetText length];
    if (expectedLocation >= targetLength) {
        expectedLocation = targetLength - 1;
    }

    NSString *targetLower = [targetText lowercaseString];
    NSUInteger bestLocation = expectedLocation;
    double bestScore = DBL_MAX;

    for (NSString *token in tokens) {
        if ([token length] == 0) {
            continue;
        }

        NSRange searchRange = NSMakeRange(0, [targetLower length]);
        while (searchRange.length > 0) {
            NSRange found = [targetLower rangeOfString:token
                                               options:0
                                                 range:searchRange];
            if (found.location == NSNotFound) {
                break;
            }

            double distance = fabs((double)((NSInteger)found.location - (NSInteger)expectedLocation));
            double tokenBonus = (double)MIN((NSUInteger)[token length], (NSUInteger)10) * 1.2;
            double score = distance - tokenBonus;
            if (score < bestScore) {
                bestScore = score;
                bestLocation = found.location;
            }

            NSUInteger nextStart = NSMaxRange(found);
            if (nextStart >= [targetLower length]) {
                break;
            }
            searchRange = NSMakeRange(nextStart, [targetLower length] - nextStart);
        }
    }

    return bestLocation;
}

static BOOL OMDExtractAnchor(NSDictionary *anchor,
                             NSInteger *sourceStartLineOut,
                             NSInteger *sourceEndLineOut,
                             NSUInteger *targetStartOut,
                             NSUInteger *targetLengthOut)
{
    if (anchor == nil) {
        return NO;
    }

    NSNumber *sourceStartNumber = [anchor objectForKey:OMDAnchorSourceStartLineKey];
    NSNumber *sourceEndNumber = [anchor objectForKey:OMDAnchorSourceEndLineKey];
    NSNumber *targetStartNumber = [anchor objectForKey:OMDAnchorTargetStartKey];
    NSNumber *targetLengthNumber = [anchor objectForKey:OMDAnchorTargetLengthKey];
    if (sourceStartNumber == nil || sourceEndNumber == nil || targetStartNumber == nil || targetLengthNumber == nil) {
        return NO;
    }

    NSInteger sourceStartLine = [sourceStartNumber integerValue];
    NSInteger sourceEndLine = [sourceEndNumber integerValue];
    NSUInteger targetStart = [targetStartNumber unsignedIntegerValue];
    NSUInteger targetLength = [targetLengthNumber unsignedIntegerValue];

    if (sourceStartLine <= 0) {
        return NO;
    }
    if (sourceEndLine < sourceStartLine) {
        sourceEndLine = sourceStartLine;
    }

    if (sourceStartLineOut != NULL) {
        *sourceStartLineOut = sourceStartLine;
    }
    if (sourceEndLineOut != NULL) {
        *sourceEndLineOut = sourceEndLine;
    }
    if (targetStartOut != NULL) {
        *targetStartOut = targetStart;
    }
    if (targetLengthOut != NULL) {
        *targetLengthOut = targetLength;
    }
    return YES;
}

static NSDictionary *OMDBestAnchorForSourceLine(NSArray *blockAnchors, NSInteger sourceLine)
{
    NSDictionary *bestAnchor = nil;
    NSInteger bestLineSpan = NSIntegerMax;
    NSUInteger bestTargetLength = NSUIntegerMax;

    for (NSDictionary *anchor in blockAnchors) {
        NSInteger sourceStartLine = 0;
        NSInteger sourceEndLine = 0;
        NSUInteger targetLength = 0;
        if (!OMDExtractAnchor(anchor, &sourceStartLine, &sourceEndLine, NULL, &targetLength)) {
            continue;
        }
        if (targetLength == 0) {
            continue;
        }
        if (sourceLine < sourceStartLine || sourceLine > sourceEndLine) {
            continue;
        }

        NSInteger lineSpan = sourceEndLine - sourceStartLine + 1;
        if (lineSpan < 1) {
            lineSpan = 1;
        }
        if (bestAnchor == nil ||
            lineSpan < bestLineSpan ||
            (lineSpan == bestLineSpan && targetLength < bestTargetLength)) {
            bestAnchor = anchor;
            bestLineSpan = lineSpan;
            bestTargetLength = targetLength;
        }
    }
    return bestAnchor;
}

static NSDictionary *OMDBestAnchorForTargetLocation(NSArray *blockAnchors, NSUInteger targetLocation)
{
    NSDictionary *bestAnchor = nil;
    NSUInteger bestTargetLength = NSUIntegerMax;
    NSInteger bestLineSpan = NSIntegerMax;

    for (NSDictionary *anchor in blockAnchors) {
        NSInteger sourceStartLine = 0;
        NSInteger sourceEndLine = 0;
        NSUInteger targetStart = 0;
        NSUInteger targetLength = 0;
        if (!OMDExtractAnchor(anchor, &sourceStartLine, &sourceEndLine, &targetStart, &targetLength)) {
            continue;
        }
        if (targetLength == 0) {
            continue;
        }

        NSUInteger targetEnd = targetStart + targetLength;
        if (targetLocation < targetStart || targetLocation >= targetEnd) {
            continue;
        }

        NSInteger lineSpan = sourceEndLine - sourceStartLine + 1;
        if (lineSpan < 1) {
            lineSpan = 1;
        }
        if (bestAnchor == nil ||
            targetLength < bestTargetLength ||
            (targetLength == bestTargetLength && lineSpan < bestLineSpan)) {
            bestAnchor = anchor;
            bestTargetLength = targetLength;
            bestLineSpan = lineSpan;
        }
    }
    return bestAnchor;
}

static NSDictionary *OMDLineInfoForOneBasedLine(NSArray *lineInfos, NSInteger lineNumber)
{
    NSUInteger count = [lineInfos count];
    if (count == 0) {
        return nil;
    }

    NSInteger index = lineNumber - 1;
    if (index < 0) {
        index = 0;
    }
    if (index >= (NSInteger)count) {
        index = (NSInteger)count - 1;
    }
    return [lineInfos objectAtIndex:(NSUInteger)index];
}

static double OMDLineColumnRatioForLocation(NSDictionary *lineInfo, NSUInteger location)
{
    NSUInteger lineStart = OMDLineInfoStart(lineInfo);
    NSUInteger lineLength = OMDLineInfoLength(lineInfo);
    if (lineLength == 0) {
        return 0.0;
    }

    NSUInteger column = location > lineStart ? (location - lineStart) : 0;
    if (column > lineLength) {
        column = lineLength;
    }
    return (double)column / (double)lineLength;
}

static NSUInteger OMDSourceLocationFromLineAndRatio(NSArray *sourceInfos,
                                                    NSInteger lineNumber,
                                                    double columnRatio,
                                                    NSUInteger sourceLength)
{
    NSDictionary *lineInfo = OMDLineInfoForOneBasedLine(sourceInfos, lineNumber);
    if (lineInfo == nil) {
        return sourceLength;
    }

    NSUInteger lineStart = OMDLineInfoStart(lineInfo);
    NSUInteger lineLength = OMDLineInfoLength(lineInfo);
    if (columnRatio < 0.0) {
        columnRatio = 0.0;
    } else if (columnRatio > 1.0) {
        columnRatio = 1.0;
    }

    NSUInteger lineColumn = 0;
    if (lineLength > 0) {
        lineColumn = (NSUInteger) llround(columnRatio * (double)lineLength);
        if (lineColumn > lineLength) {
            lineColumn = lineLength;
        }
    }

    NSUInteger mapped = lineStart + lineColumn;
    if (mapped > sourceLength) {
        mapped = sourceLength;
    }
    return mapped;
}

static BOOL OMDNodeLineBounds(cmark_node *node, NSInteger *startLineOut, NSInteger *endLineOut)
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
        *startLineOut = (NSInteger)startLine;
    }
    if (endLineOut != NULL) {
        *endLineOut = (NSInteger)endLine;
    }
    return YES;
}

static BOOL OMDNodeTypeHasBlockAnchor(cmark_node_type type)
{
    switch (type) {
        case CMARK_NODE_PARAGRAPH:
        case CMARK_NODE_HEADING:
        case CMARK_NODE_CODE_BLOCK:
        case CMARK_NODE_THEMATIC_BREAK:
        case CMARK_NODE_BLOCK_QUOTE:
        case CMARK_NODE_LIST:
        case CMARK_NODE_ITEM:
            return YES;
        default:
            return NO;
    }
}

static NSArray *OMDSourceLinesForMarkdown(NSString *sourceText)
{
    NSMutableArray *lines = [NSMutableArray array];
    if (sourceText == nil || [sourceText length] == 0) {
        return lines;
    }

    NSUInteger totalLength = [sourceText length];
    NSUInteger cursor = 0;
    while (cursor < totalLength) {
        NSRange lineRange = [sourceText lineRangeForRange:NSMakeRange(cursor, 0)];
        NSUInteger lineStart = lineRange.location;
        NSUInteger contentLength = lineRange.length;

        while (contentLength > 0) {
            unichar ch = [sourceText characterAtIndex:lineStart + contentLength - 1];
            if (ch == '\n' || ch == '\r') {
                contentLength -= 1;
                continue;
            }
            break;
        }

        NSString *line = [sourceText substringWithRange:NSMakeRange(lineStart, contentLength)];
        [lines addObject:line];
        cursor = NSMaxRange(lineRange);
    }
    return lines;
}

static NSString *OMDBlockSignatureForLineRange(NSArray *sourceLines,
                                               NSInteger startLine,
                                               NSInteger endLine)
{
    NSUInteger count = [sourceLines count];
    if (count == 0 || startLine <= 0) {
        return @"";
    }
    if (startLine > (NSInteger)count) {
        return @"";
    }
    if (endLine < startLine) {
        endLine = startLine;
    }
    if (endLine > (NSInteger)count) {
        endLine = (NSInteger)count;
    }

    NSMutableString *joined = [NSMutableString string];
    NSInteger line = startLine;
    for (; line <= endLine; line++) {
        NSString *lineText = [sourceLines objectAtIndex:(NSUInteger)line - 1];
        NSString *trimmed = [lineText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([joined length] > 0) {
            [joined appendString:@"\n"];
        }
        [joined appendString:trimmed];
    }
    return OMDNormalizeAnchorLine(joined);
}

static NSString *OMDStableBlockIDForNode(cmark_node *node, NSArray *sourceLines)
{
    if (node == NULL) {
        return nil;
    }

    NSInteger startLine = 0;
    NSInteger endLine = 0;
    if (!OMDNodeLineBounds(node, &startLine, &endLine)) {
        return nil;
    }

    NSString *signature = OMDBlockSignatureForLineRange(sourceLines, startLine, endLine);
    if (signature == nil || [signature length] == 0) {
        signature = @"_";
    }
    return [NSString stringWithFormat:@"%d|%@", (int)cmark_node_get_type(node), signature];
}

static void OMDCollectSourceBlockDescriptors(cmark_node *node,
                                             NSArray *sourceLines,
                                             NSMutableArray *descriptors)
{
    if (node == NULL) {
        return;
    }

    cmark_node_type type = cmark_node_get_type(node);
    if (OMDNodeTypeHasBlockAnchor(type)) {
        NSInteger startLine = 0;
        NSInteger endLine = 0;
        if (OMDNodeLineBounds(node, &startLine, &endLine)) {
            NSString *blockID = OMDStableBlockIDForNode(node, sourceLines);
            NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                               [NSNumber numberWithInteger:startLine], OMDAnchorSourceStartLineKey,
                                               [NSNumber numberWithInteger:endLine], OMDAnchorSourceEndLineKey,
                                               nil];
            if (blockID != nil && [blockID length] > 0) {
                [descriptor setObject:blockID forKey:OMDAnchorBlockIDKey];
            }
            [descriptors addObject:descriptor];
        }
    }

    cmark_node *child = cmark_node_first_child(node);
    while (child != NULL) {
        OMDCollectSourceBlockDescriptors(child, sourceLines, descriptors);
        child = cmark_node_next(child);
    }
}

static NSArray *OMDSourceBlockDescriptorsForMarkdown(NSString *sourceText)
{
    if (sourceText == nil || [sourceText length] == 0) {
        return [NSArray array];
    }

    NSData *sourceData = [sourceText dataUsingEncoding:NSUTF8StringEncoding];
    if (sourceData == nil || [sourceData length] == 0) {
        return [NSArray array];
    }

    const char *bytes = (const char *)[sourceData bytes];
    size_t length = (size_t)[sourceData length];
    cmark_node *document = cmark_parse_document(bytes, length, CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return [NSArray array];
    }

    NSArray *sourceLines = OMDSourceLinesForMarkdown(sourceText);
    NSMutableArray *descriptors = [NSMutableArray array];
    OMDCollectSourceBlockDescriptors(document, sourceLines, descriptors);
    cmark_node_free(document);
    return descriptors;
}

static NSArray *OMDSourceBlockDescriptorsForMarkdownCached(NSString *sourceText)
{
    if (sourceText == nil || [sourceText length] == 0) {
        return [NSArray array];
    }

    if ((OMDCachedSourceDescriptorText == sourceText) ||
        [OMDCachedSourceDescriptorText isEqualToString:sourceText]) {
        return OMDCachedSourceDescriptors != nil ? OMDCachedSourceDescriptors : [NSArray array];
    }

    NSArray *descriptors = OMDSourceBlockDescriptorsForMarkdown(sourceText);
    [OMDCachedSourceDescriptorText release];
    OMDCachedSourceDescriptorText = [sourceText copy];
    [OMDCachedSourceDescriptors release];
    OMDCachedSourceDescriptors = [descriptors copy];
    return OMDCachedSourceDescriptors != nil ? OMDCachedSourceDescriptors : [NSArray array];
}

static NSString *OMDAnchorBlockID(NSDictionary *anchor)
{
    id value = [anchor objectForKey:OMDAnchorBlockIDKey];
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return (NSString *)value;
    }
    return nil;
}

static NSString *OMDSourceDescriptorBlockID(NSDictionary *descriptor)
{
    id value = [descriptor objectForKey:OMDAnchorBlockIDKey];
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return (NSString *)value;
    }
    return nil;
}

static BOOL OMDAnchorsContainBlockIDs(NSArray *anchors)
{
    for (NSDictionary *anchor in anchors) {
        if (OMDAnchorBlockID(anchor) != nil) {
            return YES;
        }
    }
    return NO;
}

static NSDictionary *OMDBestSourceDescriptorForLine(NSArray *descriptors, NSInteger sourceLine)
{
    NSDictionary *best = nil;
    NSInteger bestSpan = NSIntegerMax;
    for (NSDictionary *descriptor in descriptors) {
        NSNumber *startNumber = [descriptor objectForKey:OMDAnchorSourceStartLineKey];
        NSNumber *endNumber = [descriptor objectForKey:OMDAnchorSourceEndLineKey];
        if (startNumber == nil || endNumber == nil) {
            continue;
        }

        NSInteger startLine = [startNumber integerValue];
        NSInteger endLine = [endNumber integerValue];
        if (endLine < startLine) {
            endLine = startLine;
        }
        if (sourceLine < startLine || sourceLine > endLine) {
            continue;
        }

        NSInteger span = endLine - startLine + 1;
        if (span < 1) {
            span = 1;
        }
        if (best == nil || span < bestSpan) {
            best = descriptor;
            bestSpan = span;
        }
    }
    return best;
}

static NSDictionary *OMDBestSourceDescriptorForBlockID(NSArray *descriptors,
                                                        NSString *blockID,
                                                        NSInteger expectedLine)
{
    if (blockID == nil || [blockID length] == 0) {
        return nil;
    }

    NSDictionary *best = nil;
    double bestScore = DBL_MAX;
    for (NSDictionary *descriptor in descriptors) {
        NSString *descriptorID = OMDSourceDescriptorBlockID(descriptor);
        if (descriptorID == nil || ![descriptorID isEqualToString:blockID]) {
            continue;
        }

        NSNumber *startNumber = [descriptor objectForKey:OMDAnchorSourceStartLineKey];
        NSNumber *endNumber = [descriptor objectForKey:OMDAnchorSourceEndLineKey];
        if (startNumber == nil || endNumber == nil) {
            continue;
        }

        NSInteger startLine = [startNumber integerValue];
        NSInteger endLine = [endNumber integerValue];
        if (endLine < startLine) {
            endLine = startLine;
        }
        NSInteger span = endLine - startLine + 1;
        if (span < 1) {
            span = 1;
        }

        double distance = 0.0;
        if (expectedLine > 0) {
            NSInteger center = startLine + (span / 2);
            distance = fabs((double)(center - expectedLine));
        }
        double score = (distance * 1000.0) + (double)span;
        if (score < bestScore) {
            bestScore = score;
            best = descriptor;
        }
    }
    return best;
}

static NSInteger OMDSourceDescriptorOrdinalForBlockID(NSArray *descriptors,
                                                      NSDictionary *targetDescriptor,
                                                      NSString *blockID)
{
    if (blockID == nil || [blockID length] == 0 || targetDescriptor == nil) {
        return NSNotFound;
    }

    NSInteger ordinal = 0;
    for (NSDictionary *descriptor in descriptors) {
        NSString *descriptorID = OMDSourceDescriptorBlockID(descriptor);
        if (descriptorID == nil || ![descriptorID isEqualToString:blockID]) {
            continue;
        }
        if (descriptor == targetDescriptor || [descriptor isEqual:targetDescriptor]) {
            return ordinal;
        }
        ordinal += 1;
    }
    return NSNotFound;
}

static NSDictionary *OMDBestAnchorForBlockID(NSArray *blockAnchors,
                                              NSString *blockID,
                                              NSUInteger expectedTargetLocation)
{
    if (blockID == nil || [blockID length] == 0) {
        return nil;
    }

    NSDictionary *best = nil;
    double bestScore = DBL_MAX;
    for (NSDictionary *anchor in blockAnchors) {
        NSString *anchorID = OMDAnchorBlockID(anchor);
        if (anchorID == nil || ![anchorID isEqualToString:blockID]) {
            continue;
        }

        NSUInteger targetStart = 0;
        NSUInteger targetLength = 0;
        if (!OMDExtractAnchor(anchor, NULL, NULL, &targetStart, &targetLength) || targetLength == 0) {
            continue;
        }

        NSUInteger center = targetStart + (targetLength / 2);
        double distance = fabs((double)((NSInteger)center - (NSInteger)expectedTargetLocation));
        double score = (distance * 1000.0) + (double)targetLength;
        if (score < bestScore) {
            bestScore = score;
            best = anchor;
        }
    }
    return best;
}

static NSInteger OMDAnchorOrdinalForBlockID(NSArray *blockAnchors,
                                            NSDictionary *targetAnchor,
                                            NSString *blockID)
{
    if (blockID == nil || [blockID length] == 0 || targetAnchor == nil) {
        return NSNotFound;
    }

    NSInteger ordinal = 0;
    for (NSDictionary *anchor in blockAnchors) {
        NSString *anchorID = OMDAnchorBlockID(anchor);
        if (anchorID == nil || ![anchorID isEqualToString:blockID]) {
            continue;
        }
        if (anchor == targetAnchor || [anchor isEqual:targetAnchor]) {
            return ordinal;
        }
        ordinal += 1;
    }
    return NSNotFound;
}

static NSDictionary *OMDSourceDescriptorForBlockIDWithOrdinal(NSArray *descriptors,
                                                               NSString *blockID,
                                                               NSInteger preferredOrdinal,
                                                               NSInteger expectedLine)
{
    if (blockID == nil || [blockID length] == 0) {
        return nil;
    }

    NSInteger ordinal = 0;
    for (NSDictionary *descriptor in descriptors) {
        NSString *descriptorID = OMDSourceDescriptorBlockID(descriptor);
        if (descriptorID == nil || ![descriptorID isEqualToString:blockID]) {
            continue;
        }
        if (preferredOrdinal != NSNotFound && preferredOrdinal >= 0 && ordinal == preferredOrdinal) {
            return descriptor;
        }
        ordinal += 1;
    }
    return OMDBestSourceDescriptorForBlockID(descriptors, blockID, expectedLine);
}

static NSDictionary *OMDAnchorForBlockIDWithOrdinal(NSArray *blockAnchors,
                                                     NSString *blockID,
                                                     NSInteger preferredOrdinal,
                                                     NSUInteger expectedTargetLocation)
{
    if (blockID == nil || [blockID length] == 0) {
        return nil;
    }

    NSInteger ordinal = 0;
    for (NSDictionary *anchor in blockAnchors) {
        NSString *anchorID = OMDAnchorBlockID(anchor);
        if (anchorID == nil || ![anchorID isEqualToString:blockID]) {
            continue;
        }

        NSUInteger targetLength = 0;
        if (!OMDExtractAnchor(anchor, NULL, NULL, NULL, &targetLength) || targetLength == 0) {
            continue;
        }

        if (preferredOrdinal != NSNotFound && preferredOrdinal >= 0 && ordinal == preferredOrdinal) {
            return anchor;
        }
        ordinal += 1;
    }
    return OMDBestAnchorForBlockID(blockAnchors, blockID, expectedTargetLocation);
}

double OMDNormalizedLocationRatio(NSUInteger location, NSUInteger length)
{
    if (length == 0) {
        return 0.0;
    }
    if (location > length) {
        location = length;
    }

    double ratio = (double)location / (double)length;
    if (ratio < 0.0) {
        return 0.0;
    }
    if (ratio > 1.0) {
        return 1.0;
    }
    return ratio;
}

NSUInteger OMDMapLocationBetweenLengths(NSUInteger location,
                                        NSUInteger sourceLength,
                                        NSUInteger targetLength)
{
    if (targetLength == 0) {
        return 0;
    }

    double ratio = OMDNormalizedLocationRatio(location, sourceLength);
    NSUInteger mapped = (NSUInteger) llround(ratio * (double)targetLength);
    if (mapped >= targetLength) {
        mapped = targetLength - 1;
    }
    return mapped;
}

NSUInteger OMDMapLocationBetweenTexts(NSString *sourceText,
                                      NSUInteger sourceLocation,
                                      NSString *targetText)
{
    NSUInteger sourceLength = [sourceText length];
    NSUInteger targetLength = [targetText length];
    NSUInteger expected = OMDMapLocationBetweenLengths(sourceLocation, sourceLength, targetLength);
    if (targetLength == 0) {
        return 0;
    }
    if (sourceText == nil || sourceLength == 0 || targetText == nil) {
        return expected;
    }

    NSArray *sourceInfos = OMDLineInfosForText(sourceText, YES);
    NSArray *targetInfos = OMDLineInfosForText(targetText, NO);
    if ([sourceInfos count] == 0 || [targetInfos count] == 0) {
        return expected;
    }

    NSUInteger sourceLineIndex = OMDLineIndexForLocation(sourceInfos, sourceLocation);
    if (sourceLineIndex == NSNotFound || sourceLineIndex >= [sourceInfos count]) {
        return expected;
    }
    NSDictionary *sourceLineInfo = [sourceInfos objectAtIndex:sourceLineIndex];
    OMDAnchorLineFamily sourceFamily = OMDLineInfoFamily(sourceLineInfo);
    NSString *sourceNormalized = OMDLineInfoNormalized(sourceLineInfo);
    NSArray *sourceLineTokens = OMDLineInfoTokens(sourceLineInfo);
    NSArray *anchorTokens = OMDContextTokensForSourceLine(sourceInfos, sourceLineIndex, sourceFamily);
    if ([sourceNormalized length] == 0 && [anchorTokens count] == 0) {
        return expected;
    }

    NSUInteger expectedLineIndex = OMDLineIndexForLocation(targetInfos, expected);
    NSUInteger targetLineIndex = OMDSelectBestTargetLine(targetInfos,
                                                         anchorTokens,
                                                         sourceNormalized,
                                                         sourceFamily,
                                                         expectedLineIndex);

    if (targetLineIndex == NSNotFound || targetLineIndex >= [targetInfos count]) {
        if ([anchorTokens count] > 0) {
            return OMDBestMatchLocationInText(targetText, anchorTokens, expected);
        }
        return expected;
    }

    NSDictionary *targetLineInfo = [targetInfos objectAtIndex:targetLineIndex];
    NSUInteger mapped = OMDLocationUsingLineAndColumnRatio(sourceLineInfo,
                                                           sourceLocation,
                                                           targetLineInfo,
                                                           targetLength);

    NSArray *adjustTokens = [sourceLineTokens count] > 0 ? sourceLineTokens : anchorTokens;
    if ([adjustTokens count] > 0) {
        NSUInteger tokenAdjusted = OMDBestMatchLocationInText(targetText, adjustTokens, mapped);
        NSInteger delta = (NSInteger)tokenAdjusted - (NSInteger)mapped;
        if (delta < 0) {
            delta = -delta;
        }
        if (delta <= 180) {
            mapped = tokenAdjusted;
        }
    }

    return mapped;
}

NSUInteger OMDMapSourceLocationWithBlockAnchors(NSString *sourceText,
                                                NSUInteger sourceLocation,
                                                NSString *targetText,
                                                NSArray *blockAnchors)
{
    NSUInteger expected = OMDMapLocationBetweenTexts(sourceText, sourceLocation, targetText);
    NSUInteger targetLength = [targetText length];
    if (targetLength == 0) {
        return 0;
    }
    if (sourceText == nil || targetText == nil || [blockAnchors count] == 0) {
        return expected;
    }

    NSArray *sourceInfos = OMDLineInfosForText(sourceText, NO);
    if ([sourceInfos count] == 0) {
        return expected;
    }

    NSUInteger sourceLineIndex = OMDLineIndexForLocation(sourceInfos, sourceLocation);
    if (sourceLineIndex == NSNotFound || sourceLineIndex >= [sourceInfos count]) {
        return expected;
    }

    NSInteger sourceLine = (NSInteger)sourceLineIndex + 1;
    NSArray *sourceDescriptors = [NSArray array];
    NSDictionary *sourceDescriptor = nil;
    NSString *sourceBlockID = nil;
    NSInteger sourceBlockOrdinal = NSNotFound;
    if (OMDAnchorsContainBlockIDs(blockAnchors)) {
        sourceDescriptors = OMDSourceBlockDescriptorsForMarkdownCached(sourceText);
        sourceDescriptor = OMDBestSourceDescriptorForLine(sourceDescriptors, sourceLine);
        sourceBlockID = OMDSourceDescriptorBlockID(sourceDescriptor);
        sourceBlockOrdinal = OMDSourceDescriptorOrdinalForBlockID(sourceDescriptors,
                                                                  sourceDescriptor,
                                                                  sourceBlockID);
    }

    NSDictionary *anchor = nil;
    if (sourceBlockID != nil) {
        anchor = OMDAnchorForBlockIDWithOrdinal(blockAnchors,
                                                sourceBlockID,
                                                sourceBlockOrdinal,
                                                expected);
    }
    if (anchor == nil) {
        anchor = OMDBestAnchorForSourceLine(blockAnchors, sourceLine);
    }
    if (anchor == nil) {
        return expected;
    }

    NSInteger sourceStartLine = 0;
    NSInteger sourceEndLine = 0;
    NSUInteger targetStart = 0;
    NSUInteger targetAnchorLength = 0;
    if (!OMDExtractAnchor(anchor, &sourceStartLine, &sourceEndLine, &targetStart, &targetAnchorLength) ||
        targetAnchorLength == 0) {
        return expected;
    }

    NSInteger progressStartLine = sourceStartLine;
    NSInteger progressEndLine = sourceEndLine;
    NSString *anchorBlockID = OMDAnchorBlockID(anchor);
    if (sourceDescriptor != nil && anchorBlockID != nil) {
        NSString *descriptorBlockID = OMDSourceDescriptorBlockID(sourceDescriptor);
        if (descriptorBlockID != nil && [descriptorBlockID isEqualToString:anchorBlockID]) {
            NSNumber *descriptorStart = [sourceDescriptor objectForKey:OMDAnchorSourceStartLineKey];
            NSNumber *descriptorEnd = [sourceDescriptor objectForKey:OMDAnchorSourceEndLineKey];
            if (descriptorStart != nil && descriptorEnd != nil) {
                progressStartLine = [descriptorStart integerValue];
                progressEndLine = [descriptorEnd integerValue];
            }
        }
    }

    NSInteger sourceLineSpan = progressEndLine - progressStartLine + 1;
    if (sourceLineSpan < 1) {
        sourceLineSpan = 1;
    }
    NSInteger sourceLineOffset = sourceLine - progressStartLine;
    if (sourceLineOffset < 0) {
        sourceLineOffset = 0;
    }
    if (sourceLineOffset >= sourceLineSpan) {
        sourceLineOffset = sourceLineSpan - 1;
    }

    NSDictionary *sourceLineInfo = [sourceInfos objectAtIndex:sourceLineIndex];
    double columnRatio = OMDLineColumnRatioForLocation(sourceLineInfo, sourceLocation);
    double progress = ((double)sourceLineOffset + columnRatio) / (double)sourceLineSpan;
    if (progress < 0.0) {
        progress = 0.0;
    } else if (progress > 1.0) {
        progress = 1.0;
    }

    NSUInteger mapped = targetStart;
    if (targetAnchorLength > 1) {
        mapped = targetStart + (NSUInteger) llround(progress * (double)(targetAnchorLength - 1));
    }
    if (mapped >= targetLength) {
        mapped = targetLength - 1;
    }
    return mapped;
}

NSUInteger OMDMapTargetLocationWithBlockAnchors(NSString *sourceText,
                                                NSString *targetText,
                                                NSUInteger targetLocation,
                                                NSArray *blockAnchors)
{
    NSUInteger expected = OMDMapLocationBetweenTexts(targetText, targetLocation, sourceText);
    NSUInteger sourceLength = [sourceText length];
    NSUInteger targetLength = [targetText length];
    if (sourceLength == 0) {
        return 0;
    }
    if (targetLength == 0) {
        return expected;
    }
    if (sourceText == nil || targetText == nil || [blockAnchors count] == 0) {
        return expected;
    }

    NSUInteger lookupLocation = targetLocation;
    if (lookupLocation >= targetLength) {
        lookupLocation = targetLength - 1;
    }

    NSDictionary *anchor = OMDBestAnchorForTargetLocation(blockAnchors, lookupLocation);
    if (anchor == nil) {
        return expected;
    }

    NSInteger sourceStartLine = 0;
    NSInteger sourceEndLine = 0;
    NSUInteger targetStart = 0;
    NSUInteger targetAnchorLength = 0;
    if (!OMDExtractAnchor(anchor, &sourceStartLine, &sourceEndLine, &targetStart, &targetAnchorLength) ||
        targetAnchorLength == 0) {
        return expected;
    }

    NSString *anchorBlockID = OMDAnchorBlockID(anchor);
    if (anchorBlockID != nil) {
        NSInteger anchorBlockOrdinal = OMDAnchorOrdinalForBlockID(blockAnchors,
                                                                  anchor,
                                                                  anchorBlockID);
        NSArray *sourceDescriptors = OMDSourceBlockDescriptorsForMarkdownCached(sourceText);
        NSDictionary *sourceDescriptor = OMDSourceDescriptorForBlockIDWithOrdinal(sourceDescriptors,
                                                                                  anchorBlockID,
                                                                                  anchorBlockOrdinal,
                                                                                  sourceStartLine);
        if (sourceDescriptor != nil) {
            NSNumber *descriptorStart = [sourceDescriptor objectForKey:OMDAnchorSourceStartLineKey];
            NSNumber *descriptorEnd = [sourceDescriptor objectForKey:OMDAnchorSourceEndLineKey];
            if (descriptorStart != nil && descriptorEnd != nil) {
                sourceStartLine = [descriptorStart integerValue];
                sourceEndLine = [descriptorEnd integerValue];
            }
        }
    }

    NSArray *sourceInfos = OMDLineInfosForText(sourceText, NO);
    if ([sourceInfos count] == 0) {
        return expected;
    }

    NSInteger sourceLineSpan = sourceEndLine - sourceStartLine + 1;
    if (sourceLineSpan < 1) {
        sourceLineSpan = 1;
    }

    NSUInteger targetAnchorOffset = lookupLocation > targetStart ? (lookupLocation - targetStart) : 0;
    if (targetAnchorOffset >= targetAnchorLength) {
        targetAnchorOffset = targetAnchorLength - 1;
    }

    double targetRatio = 0.0;
    if (targetAnchorLength > 1) {
        targetRatio = (double)targetAnchorOffset / (double)(targetAnchorLength - 1);
    }
    double sourceLineProgress = targetRatio * (double)sourceLineSpan;
    NSInteger sourceLineOffset = (NSInteger)floor(sourceLineProgress);
    double sourceColumnRatio = sourceLineProgress - (double)sourceLineOffset;
    if (sourceLineOffset >= sourceLineSpan) {
        sourceLineOffset = sourceLineSpan - 1;
        sourceColumnRatio = 1.0;
    }

    NSInteger sourceLineNumber = sourceStartLine + sourceLineOffset;
    NSUInteger mapped = OMDSourceLocationFromLineAndRatio(sourceInfos,
                                                          sourceLineNumber,
                                                          sourceColumnRatio,
                                                          sourceLength);
    if (mapped > sourceLength) {
        mapped = sourceLength;
    }
    return mapped;
}
