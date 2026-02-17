// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDSourceTextView.h"

static NSString * const OMDWordSelectionShimEnabledDefaultsKey = @"ObjcMarkdownWordSelectionShimEnabled";

static BOOL OMDIsMarkdownSpace(unichar ch)
{
    return ch == ' ' || ch == '\t';
}

static BOOL OMDIsMarkdownListMarker(unichar ch)
{
    return ch == '-' || ch == '*' || ch == '+';
}

static BOOL OMDIsASCIIDigit(unichar ch)
{
    return ch >= '0' && ch <= '9';
}

static BOOL OMDIsMarkdownListLine(NSString *lineText)
{
    if (lineText == nil) {
        return NO;
    }

    NSUInteger length = [lineText length];
    if (length == 0) {
        return NO;
    }

    NSUInteger cursor = 0;
    while (cursor < length && OMDIsMarkdownSpace([lineText characterAtIndex:cursor])) {
        cursor += 1;
    }

    while (cursor < length && [lineText characterAtIndex:cursor] == '>') {
        cursor += 1;
        if (cursor < length && [lineText characterAtIndex:cursor] == ' ') {
            cursor += 1;
        }
        while (cursor < length && OMDIsMarkdownSpace([lineText characterAtIndex:cursor])) {
            cursor += 1;
        }
    }

    NSUInteger remainderLength = length - cursor;
    if (remainderLength == 0) {
        return NO;
    }

    NSString *remainder = [lineText substringFromIndex:cursor];
    if (remainderLength >= 6) {
        unichar marker = [remainder characterAtIndex:0];
        unichar s1 = [remainder characterAtIndex:1];
        unichar b1 = [remainder characterAtIndex:2];
        unichar state = [remainder characterAtIndex:3];
        unichar b2 = [remainder characterAtIndex:4];
        unichar s2 = [remainder characterAtIndex:5];
        if (OMDIsMarkdownListMarker(marker) &&
            s1 == ' ' &&
            b1 == '[' &&
            (state == ' ' || state == 'x' || state == 'X') &&
            b2 == ']' &&
            s2 == ' ') {
            return YES;
        }
    }

    if (remainderLength >= 2) {
        unichar marker = [remainder characterAtIndex:0];
        unichar spacer = [remainder characterAtIndex:1];
        if (OMDIsMarkdownListMarker(marker) && spacer == ' ') {
            return YES;
        }
    }

    if (remainderLength >= 3) {
        NSUInteger digitCount = 0;
        while (digitCount < remainderLength &&
               OMDIsASCIIDigit([remainder characterAtIndex:digitCount])) {
            digitCount += 1;
        }
        if (digitCount > 0 && digitCount + 1 < remainderLength) {
            unichar delimiter = [remainder characterAtIndex:digitCount];
            unichar spacer = [remainder characterAtIndex:digitCount + 1];
            if ((delimiter == '.' || delimiter == ')') && spacer == ' ') {
                return YES;
            }
        }
    }

    return NO;
}

static NSUInteger OMDLeadingIndentRemovalLength(NSString *lineText, NSUInteger maxSpaces)
{
    if (lineText == nil || [lineText length] == 0) {
        return 0;
    }

    unichar first = [lineText characterAtIndex:0];
    if (first == '\t') {
        return 1;
    }
    if (first != ' ') {
        return 0;
    }

    NSUInteger length = [lineText length];
    NSUInteger count = 0;
    while (count < length &&
           count < maxSpaces &&
           [lineText characterAtIndex:count] == ' ') {
        count += 1;
    }
    return count;
}

static NSUInteger OMDPositionAfterInsertion(NSUInteger position,
                                            NSUInteger insertionLocation,
                                            NSUInteger insertionLength)
{
    if (position < insertionLocation) {
        return position;
    }
    return position + insertionLength;
}

static NSUInteger OMDPositionAfterRemovingRange(NSUInteger position, NSRange removalRange)
{
    if (position <= removalRange.location) {
        return position;
    }

    NSUInteger removalEnd = NSMaxRange(removalRange);
    if (position >= removalEnd) {
        return position - removalRange.length;
    }
    return removalRange.location;
}

@interface OMDSourceTextView ()
{
    NSUInteger _omdPendingModifiers;
    NSInteger _omdPendingArrowDirection;
    BOOL _omdHasPendingKeyContext;
}
- (BOOL)omdWordSelectionShimEnabled;
- (BOOL)omdSendEditorAction:(SEL)action;
- (BOOL)omdHandleStandardEditingShortcutEvent:(NSEvent *)event;
- (BOOL)omdHandleStructuredNewline:(id)sender;
- (BOOL)omdHandleListIndentationWithOutdent:(BOOL)outdent;
- (BOOL)omdHandleWordSelectionModifierEvent:(NSEvent *)event selector:(SEL)selector;
@end

@implementation OMDSourceTextView

- (void)changeFont:(id)sender
{
    id target = nil;
    NSWindow *window = [self window];
    if (window != nil) {
        id delegate = [window delegate];
        if (delegate != nil && delegate != self && [delegate respondsToSelector:@selector(changeFont:)]) {
            target = delegate;
        }
    }

    if (target == nil) {
        id appDelegate = [NSApp delegate];
        if (appDelegate != nil && appDelegate != self && [appDelegate respondsToSelector:@selector(changeFont:)]) {
            target = appDelegate;
        }
    }

    if (target != nil) {
        [NSApp sendAction:@selector(changeFont:) to:target from:sender];
        return;
    }

    [super changeFont:sender];
}

- (BOOL)omdWordSelectionShimEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:OMDWordSelectionShimEnabledDefaultsKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    _omdPendingModifiers = 0;
    _omdPendingArrowDirection = 0;
    _omdHasPendingKeyContext = NO;

    if (event != nil) {
        NSUInteger flags = [event modifierFlags];
        _omdPendingModifiers = flags & (NSControlKeyMask | NSShiftKeyMask | NSAlternateKeyMask | NSCommandKeyMask);
        _omdHasPendingKeyContext = YES;

        NSString *chars = [event charactersIgnoringModifiers];
        if ([chars length] > 0) {
            unichar ch = [chars characterAtIndex:0];
            if (ch == NSLeftArrowFunctionKey) {
                _omdPendingArrowDirection = -1;
            } else if (ch == NSRightArrowFunctionKey) {
                _omdPendingArrowDirection = 1;
            }
        }
        if (_omdPendingArrowDirection == 0) {
            chars = [event characters];
            if ([chars length] > 0) {
                unichar ch = [chars characterAtIndex:0];
                if (ch == NSLeftArrowFunctionKey) {
                    _omdPendingArrowDirection = -1;
                } else if (ch == NSRightArrowFunctionKey) {
                    _omdPendingArrowDirection = 1;
                }
            }
        }
    }

    if ([self omdHandleStandardEditingShortcutEvent:event]) {
        _omdHasPendingKeyContext = NO;
        return;
    }

    if ([self omdHandleWordSelectionModifierEvent:event selector:NULL]) {
        _omdHasPendingKeyContext = NO;
        return;
    }

    [super keyDown:event];
    _omdHasPendingKeyContext = NO;
}

- (void)doCommandBySelector:(SEL)aSelector
{
    if ([self omdHandleWordSelectionModifierEvent:[NSApp currentEvent] selector:aSelector]) {
        return;
    }
    [super doCommandBySelector:aSelector];
}

- (void)insertNewline:(id)sender
{
    if ([self omdHandleStructuredNewline:sender]) {
        return;
    }
    [super insertNewline:sender];
}

- (void)insertTab:(id)sender
{
    if ([self omdHandleListIndentationWithOutdent:NO]) {
        return;
    }
    [super insertTab:sender];
}

- (void)insertBacktab:(id)sender
{
    if ([self omdHandleListIndentationWithOutdent:YES]) {
        return;
    }
    [super insertBacktab:sender];
}

- (BOOL)omdHandleStandardEditingShortcutEvent:(NSEvent *)event
{
    if (event == nil) {
        return NO;
    }

    NSUInteger normalized = [event modifierFlags] & (NSControlKeyMask | NSShiftKeyMask | NSAlternateKeyMask | NSCommandKeyMask);
    BOOL hasControl = (normalized & NSControlKeyMask) != 0;
    BOOL hasCommand = (normalized & NSCommandKeyMask) != 0;
    BOOL hasShift = (normalized & NSShiftKeyMask) != 0;
    BOOL hasAlternate = (normalized & NSAlternateKeyMask) != 0;

    if (hasAlternate) {
        return NO;
    }
    if (!hasControl && !hasCommand) {
        return NO;
    }
    if (hasControl && hasCommand) {
        return NO;
    }

    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] != 1) {
        return NO;
    }

    unichar key = [chars characterAtIndex:0];
    if (key >= 'A' && key <= 'Z') {
        key = (unichar)(key - 'A' + 'a');
    }

    SEL action = NULL;
    BOOL allowShift = NO;
    switch (key) {
        case 'b':
            return [self omdSendEditorAction:@selector(toggleBoldFormatting:)];
        case 'i':
            return [self omdSendEditorAction:@selector(toggleItalicFormatting:)];
        case 'c':
            action = @selector(copy:);
            break;
        case 'x':
            action = @selector(cut:);
            break;
        case 'v':
            action = @selector(paste:);
            break;
        case 'a':
            action = @selector(selectAll:);
            break;
        case 'z':
            action = hasShift ? @selector(redo:) : @selector(undo:);
            allowShift = YES;
            break;
        case 'y':
            action = @selector(redo:);
            break;
        default:
            return NO;
    }

    if (action == NULL) {
        return NO;
    }
    if (hasShift && !allowShift) {
        return NO;
    }

    if (![NSApp sendAction:action to:nil from:self] &&
        [self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:action withObject:self];
#pragma clang diagnostic pop
    }
    return YES;
}

- (BOOL)omdSendEditorAction:(SEL)action
{
    if (action == NULL) {
        return NO;
    }

    NSWindow *window = [self window];
    id target = nil;
    if (window != nil) {
        id delegate = [window delegate];
        if (delegate != nil && [delegate respondsToSelector:action]) {
            target = delegate;
        }
    }
    if (target == nil) {
        id appDelegate = [NSApp delegate];
        if (appDelegate != nil && [appDelegate respondsToSelector:action]) {
            target = appDelegate;
        }
    }
    if (target == nil) {
        return NO;
    }

    if ([NSApp sendAction:action to:target from:self]) {
        return YES;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [target performSelector:action withObject:self];
#pragma clang diagnostic pop
    return YES;
}

- (BOOL)omdHandleStructuredNewline:(id)sender
{
    (void)sender;
    if (![self isEditable]) {
        return NO;
    }

    NSRange selection = [self selectedRange];
    if (selection.length != 0) {
        return NO;
    }

    NSString *source = [self string];
    if (source == nil) {
        source = @"";
    }
    if (selection.location > [source length]) {
        return NO;
    }

    NSUInteger probeLocation = selection.location;
    if (probeLocation == [source length] && probeLocation > 0) {
        probeLocation -= 1;
    }

    NSRange lineRange = [source lineRangeForRange:NSMakeRange(probeLocation, 0)];
    if (lineRange.location > [source length] || NSMaxRange(lineRange) > [source length]) {
        return NO;
    }

    NSString *lineText = [source substringWithRange:lineRange];
    if ([lineText hasSuffix:@"\n"]) {
        lineText = [lineText substringToIndex:[lineText length] - 1];
    }

    NSUInteger lineEnd = lineRange.location + [lineText length];
    if (selection.location != lineEnd) {
        return NO;
    }

    NSUInteger lineLength = [lineText length];
    NSUInteger cursor = 0;
    while (cursor < lineLength && OMDIsMarkdownSpace([lineText characterAtIndex:cursor])) {
        cursor += 1;
    }

    NSMutableString *prefix = [NSMutableString stringWithString:[lineText substringToIndex:cursor]];
    BOOL hasQuotePrefix = NO;
    while (cursor < lineLength && [lineText characterAtIndex:cursor] == '>') {
        hasQuotePrefix = YES;
        [prefix appendString:@">"];
        cursor += 1;
        if (cursor < lineLength && [lineText characterAtIndex:cursor] == ' ') {
            [prefix appendString:@" "];
            cursor += 1;
        }
        while (cursor < lineLength && OMDIsMarkdownSpace([lineText characterAtIndex:cursor])) {
            unichar spaceChar = [lineText characterAtIndex:cursor];
            [prefix appendString:[NSString stringWithFormat:@"%C", spaceChar]];
            cursor += 1;
        }
    }

    NSString *remainder = [lineText substringFromIndex:cursor];
    NSUInteger remainderLength = [remainder length];
    NSString *prefixToRemove = nil;
    NSString *continuationPrefix = nil;
    NSString *content = nil;

    if (remainderLength >= 6) {
        unichar marker = [remainder characterAtIndex:0];
        unichar s1 = [remainder characterAtIndex:1];
        unichar b1 = [remainder characterAtIndex:2];
        unichar state = [remainder characterAtIndex:3];
        unichar b2 = [remainder characterAtIndex:4];
        unichar s2 = [remainder characterAtIndex:5];
        if (OMDIsMarkdownListMarker(marker) &&
            s1 == ' ' &&
            b1 == '[' &&
            (state == ' ' || state == 'x' || state == 'X') &&
            b2 == ']' &&
            s2 == ' ') {
            NSString *itemPrefix = [remainder substringToIndex:6];
            prefixToRemove = [prefix stringByAppendingString:itemPrefix];
            continuationPrefix = [NSString stringWithFormat:@"%@%C [ ] ", prefix, marker];
            content = [remainder substringFromIndex:6];
        }
    }

    if (prefixToRemove == nil && remainderLength >= 2) {
        unichar marker = [remainder characterAtIndex:0];
        unichar spacer = [remainder characterAtIndex:1];
        if (OMDIsMarkdownListMarker(marker) && spacer == ' ') {
            NSString *itemPrefix = [remainder substringToIndex:2];
            prefixToRemove = [prefix stringByAppendingString:itemPrefix];
            continuationPrefix = [NSString stringWithFormat:@"%@%C ", prefix, marker];
            content = [remainder substringFromIndex:2];
        }
    }

    if (prefixToRemove == nil && remainderLength >= 3) {
        NSUInteger digitCount = 0;
        while (digitCount < remainderLength && OMDIsASCIIDigit([remainder characterAtIndex:digitCount])) {
            digitCount += 1;
        }
        if (digitCount > 0 && digitCount + 1 < remainderLength) {
            unichar delimiter = [remainder characterAtIndex:digitCount];
            unichar spacer = [remainder characterAtIndex:digitCount + 1];
            if ((delimiter == '.' || delimiter == ')') && spacer == ' ') {
                NSString *numberString = [remainder substringToIndex:digitCount];
                NSInteger number = [numberString integerValue];
                if (number < 0) {
                    number = 0;
                }
                NSString *itemPrefix = [remainder substringToIndex:(digitCount + 2)];
                NSString *delimiterString = [NSString stringWithFormat:@"%C", delimiter];
                prefixToRemove = [prefix stringByAppendingString:itemPrefix];
                continuationPrefix = [NSString stringWithFormat:@"%@%ld%@ ",
                                                                prefix,
                                                                (long)(number + 1),
                                                                delimiterString];
                content = [remainder substringFromIndex:(digitCount + 2)];
            }
        }
    }

    if (prefixToRemove == nil && hasQuotePrefix) {
        prefixToRemove = prefix;
        continuationPrefix = prefix;
        content = remainder;
    }

    if (prefixToRemove == nil || continuationPrefix == nil || content == nil) {
        return NO;
    }

    NSString *trimmedContent = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmedContent length] == 0) {
        NSRange removeRange = NSMakeRange(lineRange.location, [prefixToRemove length]);
        if (NSMaxRange(removeRange) > [source length]) {
            return NO;
        }
        if (![self shouldChangeTextInRange:removeRange replacementString:@""]) {
            return YES;
        }
        NSTextStorage *storage = [self textStorage];
        [storage beginEditing];
        [storage replaceCharactersInRange:removeRange withString:@""];
        [storage endEditing];
        [self didChangeText];
        [self setSelectedRange:NSMakeRange(lineRange.location, 0)];
        [self scrollRangeToVisible:NSMakeRange(lineRange.location, 0)];
        return YES;
    }

    NSString *insertion = [NSString stringWithFormat:@"\n%@", continuationPrefix];
    NSRange insertionRange = NSMakeRange(selection.location, 0);
    if (![self shouldChangeTextInRange:insertionRange replacementString:insertion]) {
        return YES;
    }
    NSTextStorage *storage = [self textStorage];
    [storage beginEditing];
    [storage replaceCharactersInRange:insertionRange withString:insertion];
    [storage endEditing];
    [self didChangeText];
    NSUInteger caret = selection.location + [insertion length];
    [self setSelectedRange:NSMakeRange(caret, 0)];
    [self scrollRangeToVisible:NSMakeRange(caret, 0)];
    return YES;
}

- (BOOL)omdHandleListIndentationWithOutdent:(BOOL)outdent
{
    if (![self isEditable]) {
        return NO;
    }

    NSString *source = [self string];
    if (source == nil || [source length] == 0) {
        return NO;
    }

    NSRange selection = [self selectedRange];
    NSUInteger sourceLength = [source length];
    if (selection.location > sourceLength) {
        return NO;
    }
    if (selection.length > sourceLength - selection.location) {
        selection.length = sourceLength - selection.location;
    }

    NSRange targetRange = NSMakeRange(0, 0);
    if (selection.length == 0) {
        NSUInteger probeLocation = selection.location;
        if (probeLocation == sourceLength && probeLocation > 0) {
            probeLocation -= 1;
        }
        targetRange = [source lineRangeForRange:NSMakeRange(probeLocation, 0)];
    } else {
        targetRange = [source lineRangeForRange:selection];
    }

    if (targetRange.location > sourceLength || NSMaxRange(targetRange) > sourceLength) {
        return NO;
    }

    NSMutableArray *operations = [NSMutableArray array];
    NSUInteger cursor = targetRange.location;
    NSUInteger targetEnd = NSMaxRange(targetRange);
    while (cursor < targetEnd) {
        NSRange lineRange = [source lineRangeForRange:NSMakeRange(cursor, 0)];
        if (lineRange.location >= targetEnd) {
            break;
        }
        if (NSMaxRange(lineRange) > sourceLength) {
            break;
        }

        NSString *lineText = [source substringWithRange:lineRange];
        if ([lineText hasSuffix:@"\n"]) {
            lineText = [lineText substringToIndex:[lineText length] - 1];
        }

        if (OMDIsMarkdownListLine(lineText)) {
            if (outdent) {
                NSUInteger removeCount = OMDLeadingIndentRemovalLength(lineText, 4);
                if (removeCount > 0) {
                    [operations addObject:@{
                        @"range": [NSValue valueWithRange:NSMakeRange(lineRange.location, removeCount)],
                        @"replacement": @""
                    }];
                }
            } else {
                [operations addObject:@{
                    @"range": [NSValue valueWithRange:NSMakeRange(lineRange.location, 0)],
                    @"replacement": @"    "
                }];
            }
        }

        NSUInteger nextCursor = NSMaxRange(lineRange);
        if (nextCursor <= cursor) {
            break;
        }
        cursor = nextCursor;
    }

    if ([operations count] == 0) {
        return NO;
    }

    NSEnumerator *forward = [operations objectEnumerator];
    NSDictionary *operation = nil;
    while ((operation = [forward nextObject]) != nil) {
        NSRange range = [[operation objectForKey:@"range"] rangeValue];
        NSString *replacement = [operation objectForKey:@"replacement"];
        if (![self shouldChangeTextInRange:range replacementString:replacement]) {
            return YES;
        }
    }

    NSTextStorage *storage = [self textStorage];
    NSUInteger selectionStart = selection.location;
    NSUInteger selectionEnd = selection.location + selection.length;

    [storage beginEditing];
    for (NSInteger index = (NSInteger)[operations count] - 1; index >= 0; index -= 1) {
        NSDictionary *current = [operations objectAtIndex:(NSUInteger)index];
        NSRange range = [[current objectForKey:@"range"] rangeValue];
        NSString *replacement = [current objectForKey:@"replacement"];
        [storage replaceCharactersInRange:range withString:replacement];

        if (range.length == 0 && [replacement length] > 0) {
            NSUInteger insertLength = [replacement length];
            selectionStart = OMDPositionAfterInsertion(selectionStart, range.location, insertLength);
            selectionEnd = OMDPositionAfterInsertion(selectionEnd, range.location, insertLength);
        } else if (range.length > 0 && [replacement length] == 0) {
            selectionStart = OMDPositionAfterRemovingRange(selectionStart, range);
            selectionEnd = OMDPositionAfterRemovingRange(selectionEnd, range);
        }
    }
    [storage endEditing];

    [self didChangeText];

    NSUInteger updatedLength = [[self string] length];
    if (selectionStart > updatedLength) {
        selectionStart = updatedLength;
    }
    if (selectionEnd > updatedLength) {
        selectionEnd = updatedLength;
    }
    if (selectionEnd < selectionStart) {
        selectionEnd = selectionStart;
    }

    NSRange updatedSelection = NSMakeRange(selectionStart, selectionEnd - selectionStart);
    [self setSelectedRange:updatedSelection];
    [self scrollRangeToVisible:NSMakeRange(updatedSelection.location, 0)];
    return YES;
}

- (BOOL)omdHandleWordSelectionModifierEvent:(NSEvent *)event selector:(SEL)selector
{
    if (![self omdWordSelectionShimEnabled]) {
        return NO;
    }

    NSUInteger normalized = 0;
    if (event != nil) {
        NSUInteger flags = [event modifierFlags];
        normalized = flags & (NSControlKeyMask | NSShiftKeyMask | NSAlternateKeyMask | NSCommandKeyMask);
    } else if (_omdHasPendingKeyContext) {
        normalized = _omdPendingModifiers;
    }

    BOOL controlShift = (normalized == (NSControlKeyMask | NSShiftKeyMask));
    BOOL commandShift = (normalized == (NSCommandKeyMask | NSShiftKeyMask));
    if (!controlShift && !commandShift) {
        return NO;
    }

    BOOL isLeft = NO;
    BOOL isRight = NO;

    if (event != nil) {
        NSString *chars = [event charactersIgnoringModifiers];
        if ([chars length] > 0) {
            unichar ch = [chars characterAtIndex:0];
            if (ch == NSLeftArrowFunctionKey) {
                isLeft = YES;
            } else if (ch == NSRightArrowFunctionKey) {
                isRight = YES;
            }
        }
        if (!isLeft && !isRight) {
            chars = [event characters];
            if ([chars length] > 0) {
                unichar ch = [chars characterAtIndex:0];
                if (ch == NSLeftArrowFunctionKey) {
                    isLeft = YES;
                } else if (ch == NSRightArrowFunctionKey) {
                    isRight = YES;
                }
            }
        }
    }

    if (!isLeft && !isRight && selector != NULL) {
        if (selector == @selector(moveBackwardAndModifySelection:) ||
            selector == @selector(moveLeftAndModifySelection:) ||
            selector == @selector(moveToBeginningOfLineAndModifySelection:) ||
            selector == @selector(moveWordLeftAndModifySelection:) ||
            selector == @selector(moveWordBackwardAndModifySelection:)) {
            isLeft = YES;
        } else if (selector == @selector(moveForwardAndModifySelection:) ||
                   selector == @selector(moveRightAndModifySelection:) ||
                   selector == @selector(moveToEndOfLineAndModifySelection:) ||
                   selector == @selector(moveWordRightAndModifySelection:) ||
                   selector == @selector(moveWordForwardAndModifySelection:)) {
            isRight = YES;
        }
    }

    if (!isLeft && !isRight && _omdHasPendingKeyContext) {
        if (_omdPendingArrowDirection < 0) {
            isLeft = YES;
        } else if (_omdPendingArrowDirection > 0) {
            isRight = YES;
        }
    }

    if (isLeft) {
        [self moveWordLeftAndModifySelection:self];
        return YES;
    }
    if (isRight) {
        [self moveWordRightAndModifySelection:self];
        return YES;
    }
    return NO;
}

@end
