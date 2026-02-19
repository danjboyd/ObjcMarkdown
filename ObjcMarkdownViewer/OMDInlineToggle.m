// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDInlineToggle.h"

static BOOL OMDIsInlineWhitespace(unichar ch)
{
    return ch == ' ' || ch == '\t';
}

static NSUInteger OMDLeadingRunLengthForCharacter(NSString *text, unichar token)
{
    if (text == nil) {
        return 0;
    }
    NSUInteger length = [text length];
    NSUInteger count = 0;
    while (count < length && [text characterAtIndex:count] == token) {
        count += 1;
    }
    return count;
}

static NSUInteger OMDTrailingRunLengthForCharacter(NSString *text, unichar token)
{
    if (text == nil) {
        return 0;
    }
    NSUInteger length = [text length];
    NSUInteger count = 0;
    while (count < length && [text characterAtIndex:(length - count - 1)] == token) {
        count += 1;
    }
    return count;
}

static BOOL OMDInlineSingleCharacterWrapperToken(NSString *prefix, NSString *suffix, unichar *tokenOut)
{
    if (prefix == nil || suffix == nil) {
        return NO;
    }
    if ([prefix length] != 1 || [suffix length] != 1) {
        return NO;
    }
    unichar token = [prefix characterAtIndex:0];
    if ([suffix characterAtIndex:0] != token) {
        return NO;
    }
    if (tokenOut != NULL) {
        *tokenOut = token;
    }
    return YES;
}

static BOOL OMDInlineTextHasToggleWrapper(NSString *text,
                                          NSString *prefix,
                                          NSString *suffix)
{
    if (text == nil || prefix == nil || suffix == nil) {
        return NO;
    }
    NSUInteger prefixLength = [prefix length];
    NSUInteger suffixLength = [suffix length];
    if (prefixLength == 0 || suffixLength == 0) {
        return NO;
    }
    if ([text length] < prefixLength + suffixLength) {
        return NO;
    }
    if (![text hasPrefix:prefix] || ![text hasSuffix:suffix]) {
        return NO;
    }

    unichar token = 0;
    if (!OMDInlineSingleCharacterWrapperToken(prefix, suffix, &token)) {
        return YES;
    }

    NSUInteger leadingRun = OMDLeadingRunLengthForCharacter(text, token);
    NSUInteger trailingRun = OMDTrailingRunLengthForCharacter(text, token);
    return ((leadingRun % 2) == 1) && ((trailingRun % 2) == 1);
}

BOOL OMDComputeInlineToggleEdit(NSString *source,
                                NSRange selection,
                                NSString *prefix,
                                NSString *suffix,
                                NSString *placeholder,
                                NSRange *replaceRangeOut,
                                NSString **replacementOut,
                                NSRange *nextSelectionOut)
{
    NSString *resolvedSource = (source != nil ? source : @"");
    NSUInteger sourceLength = [resolvedSource length];
    if (selection.location > sourceLength) {
        selection.location = sourceLength;
        selection.length = 0;
    }
    if (selection.length > sourceLength - selection.location) {
        selection.length = sourceLength - selection.location;
    }

    NSString *resolvedPrefix = (prefix != nil ? prefix : @"");
    NSString *resolvedSuffix = (suffix != nil ? suffix : @"");
    NSUInteger prefixLength = [resolvedPrefix length];
    NSUInteger suffixLength = [resolvedSuffix length];

    NSRange replaceRange = selection;
    NSRange nextSelection = selection;
    NSString *replacement = nil;

    if (selection.length > 0) {
        NSString *selectedText = [resolvedSource substringWithRange:selection];

        // For multiline selections, normalize mixed states on first toggle
        // and unwrap all lines on second toggle.
        if (prefixLength > 0 &&
            suffixLength > 0 &&
            [selectedText rangeOfString:@"\n"].location != NSNotFound) {
            NSArray *lines = [selectedText componentsSeparatedByString:@"\n"];
            BOOL sawToggleEligibleLine = NO;
            BOOL allLinesWrapped = YES;
            NSMutableArray *lineMetadata = [NSMutableArray arrayWithCapacity:[lines count]];

            for (NSString *line in lines) {
                NSString *work = (line != nil ? line : @"");
                NSUInteger length = [work length];
                NSUInteger leadingWhitespace = 0;
                while (leadingWhitespace < length &&
                       OMDIsInlineWhitespace([work characterAtIndex:leadingWhitespace])) {
                    leadingWhitespace += 1;
                }

                NSUInteger trailingWhitespace = 0;
                while (trailingWhitespace < length - leadingWhitespace &&
                       OMDIsInlineWhitespace([work characterAtIndex:(length - trailingWhitespace - 1)])) {
                    trailingWhitespace += 1;
                }

                NSUInteger coreLength = length - leadingWhitespace - trailingWhitespace;
                BOOL wrapped = NO;
                if (coreLength > 0) {
                    sawToggleEligibleLine = YES;
                    NSString *core = [work substringWithRange:NSMakeRange(leadingWhitespace, coreLength)];
                    wrapped = OMDInlineTextHasToggleWrapper(core, resolvedPrefix, resolvedSuffix);
                    if (!wrapped) {
                        allLinesWrapped = NO;
                    }
                }

                NSDictionary *meta = @{
                    @"line": work,
                    @"leading": [NSNumber numberWithUnsignedInteger:leadingWhitespace],
                    @"trailing": [NSNumber numberWithUnsignedInteger:trailingWhitespace],
                    @"coreLength": [NSNumber numberWithUnsignedInteger:coreLength],
                    @"wrapped": [NSNumber numberWithBool:wrapped]
                };
                [lineMetadata addObject:meta];
            }

            if (sawToggleEligibleLine) {
                NSMutableArray *updatedLines = [NSMutableArray arrayWithCapacity:[lineMetadata count]];
                NSEnumerator *lineEnum = [lineMetadata objectEnumerator];
                NSDictionary *meta = nil;
                while ((meta = [lineEnum nextObject]) != nil) {
                    NSString *line = [meta objectForKey:@"line"];
                    NSUInteger leadingWhitespace = [[meta objectForKey:@"leading"] unsignedIntegerValue];
                    NSUInteger trailingWhitespace = [[meta objectForKey:@"trailing"] unsignedIntegerValue];
                    NSUInteger coreLength = [[meta objectForKey:@"coreLength"] unsignedIntegerValue];
                    BOOL wrapped = [[meta objectForKey:@"wrapped"] boolValue];

                    if (coreLength == 0) {
                        [updatedLines addObject:line];
                        continue;
                    }

                    NSUInteger lineLength = [line length];
                    NSString *leading = [line substringToIndex:leadingWhitespace];
                    NSString *trailing = [line substringFromIndex:(lineLength - trailingWhitespace)];
                    NSString *core = [line substringWithRange:NSMakeRange(leadingWhitespace, coreLength)];
                    NSString *nextCore = core;

                    if (allLinesWrapped) {
                        if (wrapped && [core length] >= prefixLength + suffixLength) {
                            NSRange unwrapRange = NSMakeRange(prefixLength, [core length] - prefixLength - suffixLength);
                            nextCore = [core substringWithRange:unwrapRange];
                        }
                    } else if (!wrapped) {
                        nextCore = [NSString stringWithFormat:@"%@%@%@", resolvedPrefix, core, resolvedSuffix];
                    }

                    NSString *updatedLine = [NSString stringWithFormat:@"%@%@%@", leading, nextCore, trailing];
                    [updatedLines addObject:updatedLine];
                }

                replacement = [updatedLines componentsJoinedByString:@"\n"];
                replaceRange = selection;
                nextSelection = NSMakeRange(selection.location, [replacement length]);
                if (replaceRangeOut != NULL) {
                    *replaceRangeOut = replaceRange;
                }
                if (replacementOut != NULL) {
                    *replacementOut = replacement;
                }
                if (nextSelectionOut != NULL) {
                    *nextSelectionOut = nextSelection;
                }
                return YES;
            }
        }

        // Toggle-off path 1: selection itself includes both wrappers.
        if (OMDInlineTextHasToggleWrapper(selectedText, resolvedPrefix, resolvedSuffix)) {
            NSRange unwrapRange = NSMakeRange(prefixLength, [selectedText length] - prefixLength - suffixLength);
            replacement = [selectedText substringWithRange:unwrapRange];
            replaceRange = selection;
            nextSelection = NSMakeRange(selection.location, [replacement length]);
            if (replaceRangeOut != NULL) {
                *replaceRangeOut = replaceRange;
            }
            if (replacementOut != NULL) {
                *replacementOut = replacement;
            }
            if (nextSelectionOut != NULL) {
                *nextSelectionOut = nextSelection;
            }
            return YES;
        }

        // Toggle-off path 2: selection sits inside wrappers.
        BOOL hasWrappedBefore = selection.location >= prefixLength;
        BOOL hasWrappedAfter = (selection.location + selection.length + suffixLength) <= sourceLength;
        if (prefixLength > 0 &&
            suffixLength > 0 &&
            hasWrappedBefore &&
            hasWrappedAfter) {
            NSRange beforeRange = NSMakeRange(selection.location - prefixLength, prefixLength);
            NSRange afterRange = NSMakeRange(selection.location + selection.length, suffixLength);
            NSString *beforeText = [resolvedSource substringWithRange:beforeRange];
            NSString *afterText = [resolvedSource substringWithRange:afterRange];
            BOOL matchesSurroundingWrapper = [beforeText isEqualToString:resolvedPrefix] &&
                                             [afterText isEqualToString:resolvedSuffix];
            if (matchesSurroundingWrapper) {
                unichar token = 0;
                if (OMDInlineSingleCharacterWrapperToken(resolvedPrefix, resolvedSuffix, &token)) {
                    NSUInteger leftRun = 0;
                    while (selection.location > leftRun &&
                           [resolvedSource characterAtIndex:(selection.location - leftRun - 1)] == token) {
                        leftRun += 1;
                    }
                    NSUInteger rightRun = 0;
                    NSUInteger rightStart = selection.location + selection.length;
                    while (rightStart + rightRun < sourceLength &&
                           [resolvedSource characterAtIndex:(rightStart + rightRun)] == token) {
                        rightRun += 1;
                    }
                    matchesSurroundingWrapper = ((leftRun % 2) == 1) && ((rightRun % 2) == 1);
                }
            }
            if (matchesSurroundingWrapper) {
                replaceRange = NSMakeRange(selection.location - prefixLength,
                                           selection.length + prefixLength + suffixLength);
                replacement = selectedText;
                nextSelection = NSMakeRange(replaceRange.location, [replacement length]);
                if (replaceRangeOut != NULL) {
                    *replaceRangeOut = replaceRange;
                }
                if (replacementOut != NULL) {
                    *replacementOut = replacement;
                }
                if (nextSelectionOut != NULL) {
                    *nextSelectionOut = nextSelection;
                }
                return YES;
            }
        }
    }

    NSString *selectedText = @"";
    if (selection.length > 0) {
        selectedText = [resolvedSource substringWithRange:selection];
    } else if (placeholder != nil) {
        selectedText = placeholder;
    }

    replacement = [NSString stringWithFormat:@"%@%@%@",
                                             resolvedPrefix,
                                             selectedText,
                                             resolvedSuffix];
    replaceRange = selection;
    nextSelection = NSMakeRange(selection.location + prefixLength, [selectedText length]);

    if (replaceRangeOut != NULL) {
        *replaceRangeOut = replaceRange;
    }
    if (replacementOut != NULL) {
        *replacementOut = replacement;
    }
    if (nextSelectionOut != NULL) {
        *nextSelectionOut = nextSelection;
    }
    return YES;
}
