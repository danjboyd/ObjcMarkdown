// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDTextView.h"
#import "OMRenderedObject.h"

@interface OMDTextView ()
{
    NSUInteger _contextObjectIndex;
    OMRenderedObject *_contextObject;
}
@end

@implementation OMDTextView

- (void)dealloc
{
    [_documentBackgroundColor release];
    [_documentBorderColor release];
    [_codeBlockRanges release];
    [_codeBlockBackgroundColor release];
    [_codeBlockBorderColor release];
    [_blockquoteRanges release];
    [_blockquoteLineColor release];
    [_contextObject release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [self drawDocumentSurface];
    [self drawCodeBlockBackgrounds];
    [context saveGraphicsState];
    if ([context respondsToSelector:@selector(setImageInterpolation:)]) {
        [context setImageInterpolation:NSImageInterpolationHigh];
    }
    [super drawRect:dirtyRect];
    [context restoreGraphicsState];
    [self drawBlockquoteLines];
    [self drawRenderedObjectSelection];
}

- (void)drawDocumentSurface
{
    if (self.documentBackgroundColor == nil && self.documentBorderColor == nil) {
        return;
    }

    CGFloat borderWidth = self.documentBorderWidth;
    if (borderWidth < 0.0) {
        borderWidth = 0.0;
    }

    NSRect bounds = [self bounds];
    if (borderWidth > 0.0) {
        bounds = NSInsetRect(bounds, borderWidth * 0.5, borderWidth * 0.5);
    }
    if (bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return;
    }

    CGFloat radius = self.documentCornerRadius > 0.0 ? self.documentCornerRadius : 10.0;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
    if (self.documentBackgroundColor != nil) {
        [self.documentBackgroundColor setFill];
        [path fill];
    }
    if (self.documentBorderColor != nil && borderWidth > 0.0) {
        [path setLineWidth:borderWidth];
        [self.documentBorderColor setStroke];
        [path stroke];
    }
}

- (void)drawCodeBlockBackgrounds
{
    if (self.codeBlockBackgroundColor == nil || [self.codeBlockRanges count] == 0) {
        return;
    }

    NSLayoutManager *layoutManager = [self layoutManager];
    NSTextContainer *container = [self textContainer];
    if (layoutManager == nil || container == nil) {
        return;
    }

    [self.codeBlockBackgroundColor setFill];

    NSPoint origin = [self textContainerOrigin];
    NSSize inset = [self textContainerInset];
    CGFloat paddingX = self.codeBlockPadding.width;
    CGFloat paddingY = self.codeBlockPadding.height;
    CGFloat cornerRadius = self.codeBlockCornerRadius > 0.0 ? self.codeBlockCornerRadius : 6.0;
    CGFloat borderWidth = self.codeBlockBorderWidth > 0.0 ? self.codeBlockBorderWidth : 1.0;
    NSColor *borderColor = self.codeBlockBorderColor;
    CGFloat minX = origin.x + inset.width - paddingX;
    CGFloat maxX = origin.x + [self bounds].size.width - inset.width + paddingX;

    for (NSValue *value in self.codeBlockRanges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        if (glyphRange.length == 0) {
            continue;
        }

        NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];
        NSRect blockBounds = blockRect;
        blockBounds.origin.x = origin.x + blockRect.origin.x;
        blockBounds.origin.y = origin.y + blockRect.origin.y;

        blockBounds.origin.x -= paddingX;
        blockBounds.size.width += paddingX * 2.0;
        blockBounds.origin.y -= paddingY;
        blockBounds.size.height += paddingY * 2.0;

        if (blockBounds.origin.x < minX) {
            CGFloat delta = minX - blockBounds.origin.x;
            blockBounds.origin.x = minX;
            blockBounds.size.width -= delta;
        }
        CGFloat rightEdge = NSMaxX(blockBounds);
        if (rightEdge > maxX) {
            blockBounds.size.width -= (rightEdge - maxX);
        }
        if (blockBounds.size.width < 1.0 || blockBounds.size.height < 1.0) {
            continue;
        }

        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:blockBounds
                                                             xRadius:cornerRadius
                                                             yRadius:cornerRadius];
        [self.codeBlockBackgroundColor setFill];
        [path fill];
        if (borderColor != nil && borderWidth > 0.0) {
            [path setLineWidth:borderWidth];
            [borderColor setStroke];
            [path stroke];
        }
    }

}

- (void)drawBlockquoteLines
{
    if (self.blockquoteLineColor == nil || [self.blockquoteRanges count] == 0) {
        return;
    }

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    NSLayoutManager *layoutManager = [self layoutManager];
    NSTextContainer *container = [self textContainer];
    if (layoutManager == nil || container == nil) {
        [context restoreGraphicsState];
        return;
    }

    [self.blockquoteLineColor setFill];

    NSPoint origin = [self textContainerOrigin];
    NSSize inset = [self textContainerInset];
    CGFloat lineWidth = self.blockquoteLineWidth > 0.0 ? self.blockquoteLineWidth : 3.0;

    for (NSValue *value in self.blockquoteRanges) {
        NSRange charRange = [value rangeValue];
        if (charRange.length == 0) {
            continue;
        }

        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
        if (glyphRange.length == 0) {
            continue;
        }

        NSRect blockRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:container];

        NSUInteger charIndex = charRange.location;
        if (charIndex < [[self textStorage] length]) {
            (void)[[self textStorage] attributesAtIndex:charIndex effectiveRange:NULL];
        }
        CGFloat lineX = origin.x + inset.width - 24.0;
        CGFloat minX = origin.x + inset.width - 20.0;
        if (lineX < minX) {
            lineX = minX;
        }

        NSRect lineBounds = blockRect;
        lineBounds.origin.x = lineX;
        lineBounds.origin.y = origin.y + blockRect.origin.y;
        lineBounds.size.width = lineWidth;

        NSRectFill(lineBounds);
    }

    [context restoreGraphicsState];
}

#pragma mark - Rendered objects

- (OMRenderedObject *)renderedObjectAtCharacterIndex:(NSUInteger)characterIndex
{
    NSTextStorage *storage = [self textStorage];
    if (characterIndex >= [storage length]) {
        return nil;
    }
    return [storage attribute:OMRenderedObjectAttributeName atIndex:characterIndex effectiveRange:NULL];
}

- (OMRenderedObject *)renderedObjectAtPoint:(NSPoint)point characterIndex:(NSUInteger *)characterIndex
{
    NSLayoutManager *layoutManager = [self layoutManager];
    NSTextContainer *container = [self textContainer];
    if (layoutManager == nil || container == nil || [[self textStorage] length] == 0) {
        return nil;
    }
    NSPoint origin = [self textContainerOrigin];
    NSPoint containerPoint = NSMakePoint(point.x - origin.x, point.y - origin.y);
    NSUInteger glyphIndex = [layoutManager glyphIndexForPoint:containerPoint inTextContainer:container];
    if (glyphIndex >= [layoutManager numberOfGlyphs]) {
        return nil;
    }
    // Check the glyph's own box: glyphIndexForPoint: also answers for points
    // beside or below the nearest glyph.
    NSRect glyphRect = [layoutManager boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1)
                                                inTextContainer:container];
    if (!NSPointInRect(containerPoint, glyphRect)) {
        return nil;
    }
    NSUInteger index = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
    OMRenderedObject *object = [self renderedObjectAtCharacterIndex:index];
    if (object != nil && characterIndex != NULL) {
        *characterIndex = index;
    }
    return object;
}

- (NSImage *)imageForRenderedObjectAtIndex:(NSUInteger)characterIndex
{
    NSTextStorage *storage = [self textStorage];
    if (characterIndex >= [storage length]) {
        return nil;
    }
    NSTextAttachment *attachment = [storage attribute:NSAttachmentAttributeName
                                              atIndex:characterIndex
                                       effectiveRange:NULL];
    id<NSTextAttachmentCell> cell = [attachment attachmentCell];
    if (cell == nil) {
        return nil;
    }
    // Plain image cells (math, pictures) already hold the image.
    if ([(NSObject *)cell isMemberOfClass:[NSTextAttachmentCell class]] && [(NSCell *)cell image] != nil) {
        return [[[(NSCell *)cell image] copy] autorelease];
    }
    NSSize size = [cell cellSize];
    if (size.width < 1.0 || size.height < 1.0) {
        return nil;
    }
    // Table and diagram cells draw themselves; a nil view means unflipped.
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [cell drawWithFrame:NSMakeRect(0.0, 0.0, size.width, size.height) inView:nil];
    [image unlockFocus];
    return image;
}

// The single object the selection covers, if it covers exactly one.
- (OMRenderedObject *)selectedRenderedObject:(NSUInteger *)characterIndex
{
    NSRange selection = [self selectedRange];
    if (selection.location == NSNotFound || selection.length != 1) {
        return nil;
    }
    OMRenderedObject *object = [self renderedObjectAtCharacterIndex:selection.location];
    if (object != nil && characterIndex != NULL) {
        *characterIndex = selection.location;
    }
    return object;
}

- (BOOL)selectionContainsRenderedObject
{
    NSRange selection = [self selectedRange];
    NSTextStorage *storage = [self textStorage];
    if (selection.location == NSNotFound || selection.length == 0 || NSMaxRange(selection) > [storage length]) {
        return NO;
    }
    BOOL found = NO;
    NSUInteger index = selection.location;
    while (index < NSMaxRange(selection) && !found) {
        NSRange effective;
        id object = [storage attribute:OMRenderedObjectAttributeName
                               atIndex:index
                 longestEffectiveRange:&effective
                               inRange:selection];
        found = (object != nil);
        index = NSMaxRange(effective);
    }
    return found;
}

// The selection with each rendered object replaced by its Markdown.
- (NSAttributedString *)selectionWithObjectsAsMarkdown
{
    NSRange selection = [self selectedRange];
    NSMutableAttributedString *copy = [[[[self textStorage] attributedSubstringFromRange:selection] mutableCopy] autorelease];
    NSInteger index = (NSInteger)[copy length] - 1;
    for (; index >= 0; index--) {
        OMRenderedObject *object = [copy attribute:OMRenderedObjectAttributeName
                                           atIndex:(NSUInteger)index
                                    effectiveRange:NULL];
        if (object == nil) {
            continue;
        }
        NSMutableDictionary *attributes = [[[copy attributesAtIndex:(NSUInteger)index effectiveRange:NULL] mutableCopy] autorelease];
        [attributes removeObjectForKey:NSAttachmentAttributeName];
        [attributes removeObjectForKey:OMRenderedObjectAttributeName];
        NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:[object markdown]
                                                                           attributes:attributes] autorelease];
        [copy replaceCharactersInRange:NSMakeRange((NSUInteger)index, 1) withAttributedString:replacement];
    }
    return copy;
}

#pragma mark - Object selection

// The object's box in view coordinates, or NSZeroRect.
- (NSRect)viewRectForRenderedObjectAtIndex:(NSUInteger)characterIndex
{
    NSLayoutManager *layoutManager = [self layoutManager];
    NSTextContainer *container = [self textContainer];
    if (layoutManager == nil || container == nil || characterIndex >= [[self textStorage] length]) {
        return NSZeroRect;
    }
    NSRange glyphs = [layoutManager glyphRangeForCharacterRange:NSMakeRange(characterIndex, 1)
                                           actualCharacterRange:NULL];
    if (glyphs.length == 0) {
        return NSZeroRect;
    }
    NSRect box = [layoutManager boundingRectForGlyphRange:glyphs inTextContainer:container];
    NSPoint origin = [self textContainerOrigin];
    return NSOffsetRect(box, origin.x, origin.y);
}

// Indexes of the rendered objects inside range.
- (NSIndexSet *)renderedObjectIndexesInRange:(NSRange)range
{
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    NSTextStorage *storage = [self textStorage];
    if (range.location == NSNotFound || range.length == 0 || NSMaxRange(range) > [storage length]) {
        return indexes;
    }
    NSUInteger index = range.location;
    while (index < NSMaxRange(range)) {
        NSRange effective;
        id object = [storage attribute:OMRenderedObjectAttributeName
                               atIndex:index
                 longestEffectiveRange:&effective
                               inRange:range];
        if (object != nil) {
            [indexes addIndexesInRange:effective];
        }
        index = NSMaxRange(effective);
    }
    return indexes;
}

- (void)invalidateRenderedObjectsInRange:(NSRange)range
{
    NSIndexSet *indexes = [self renderedObjectIndexesInRange:range];
    NSUInteger index = [indexes firstIndex];
    while (index != NSNotFound) {
        NSRect rect = [self viewRectForRenderedObjectAtIndex:index];
        if (!NSIsEmptyRect(rect)) {
            [self setNeedsDisplayInRect:NSInsetRect(rect, -6.0, -6.0)];
        }
        index = [indexes indexGreaterThanIndex:index];
    }
}

// GNUstep paints the selection under attachments, and table and diagram cells
// fill their boxes, so a selected object gets an outline drawn over it.
- (void)drawRenderedObjectSelection
{
    NSIndexSet *indexes = [self renderedObjectIndexesInRange:[self selectedRange]];
    if ([indexes count] == 0) {
        return;
    }
    BOOL active = [[self window] isKeyWindow] && [[self window] firstResponder] == self;
    NSColor *accent = active ? [NSColor selectedControlColor] : [NSColor controlShadowColor];
    // Named system colours ignore colorWithAlphaComponent: in GNUstep, so
    // resolve to RGB before deriving the translucent tint.
    NSColor *rgbAccent = [accent colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (rgbAccent == nil) {
        rgbAccent = [NSColor colorWithCalibratedRed:0.21 green:0.52 blue:0.89 alpha:1.0];
    }
    accent = rgbAccent;
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];
    NSUInteger index = [indexes firstIndex];
    while (index != NSNotFound) {
        NSRect rect = [self viewRectForRenderedObjectAtIndex:index];
        if (!NSIsEmptyRect(rect)) {
            NSRect outline = NSInsetRect(NSIntegralRect(rect), -3.0, -3.0);
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:outline xRadius:4.0 yRadius:4.0];
            [[accent colorWithAlphaComponent:0.12] set];
            [path fill];
            [path setLineWidth:2.0];
            [accent set];
            [path stroke];
        }
        index = [indexes indexGreaterThanIndex:index];
    }
    [context restoreGraphicsState];
}

- (void)setSelectedRange:(NSRange)charRange
                affinity:(NSSelectionAffinity)affinity
          stillSelecting:(BOOL)stillSelecting
{
    [self invalidateRenderedObjectsInRange:[self selectedRange]];
    [super setSelectedRange:charRange affinity:affinity stillSelecting:stillSelecting];
    [self invalidateRenderedObjectsInRange:[self selectedRange]];
}

- (BOOL)becomeFirstResponder
{
    BOOL accepted = [super becomeFirstResponder];
    [self invalidateRenderedObjectsInRange:[self selectedRange]];
    return accepted;
}

- (BOOL)resignFirstResponder
{
    BOOL resigned = [super resignFirstResponder];
    [self invalidateRenderedObjectsInRange:[self selectedRange]];
    return resigned;
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSUInteger index = NSNotFound;
    OMRenderedObject *object = [self renderedObjectAtPoint:point characterIndex:&index];
    BOOL extending = ([event modifierFlags] & NSShiftKeyMask) != 0;
    // Let NSTextView track first, so a drag that starts on an object still
    // selects text. A plain click on an object then selects the whole object;
    // GNUstep would otherwise hand it to the cell, or place a caret beside it.
    [super mouseDown:event];
    if (object == nil || extending) {
        return;
    }
    if ([self selectedRange].length == 0 || [event clickCount] >= 2) {
        [self setSelectedRange:NSMakeRange(index, 1)];
    }
}

- (void)keyDown:(NSEvent *)event
{
    NSString *characters = [event charactersIgnoringModifiers];
    NSRange selection = [self selectedRange];
    if (![self isEditable] && selection.length > 0 &&
        [characters length] == 1 && [characters characterAtIndex:0] == 0x1B) {
        [self setSelectedRange:NSMakeRange(selection.location, 0)];
        return;
    }
    [super keyDown:event];
}

#pragma mark - Tool tips

- (void)updateRenderedObjectToolTips
{
    [self removeAllToolTips];
    NSIndexSet *indexes = [self renderedObjectIndexesInRange:NSMakeRange(0, [[self textStorage] length])];
    NSUInteger index = [indexes firstIndex];
    while (index != NSNotFound) {
        NSRect rect = [self viewRectForRenderedObjectAtIndex:index];
        if (!NSIsEmptyRect(rect)) {
            [self addToolTipRect:rect owner:self userData:(void *)(uintptr_t)index];
        }
        index = [indexes indexGreaterThanIndex:index];
    }
}

- (NSString *)view:(NSView *)view
  stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point
          userData:(void *)userData
{
    OMRenderedObject *object = [self renderedObjectAtCharacterIndex:(NSUInteger)(uintptr_t)userData];
    NSString *source = [object source];
    if (source == nil) {
        return nil;
    }
    source = [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([source length] > 400) {
        source = [[source substringToIndex:400] stringByAppendingString:@"…"];
    }
    return source;
}

#pragma mark - Pasteboard

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
    if ([self selectedRenderedObject:NULL] != nil && ![types containsObject:NSTIFFPboardType]) {
        types = [types arrayByAddingObject:NSTIFFPboardType];
    }
    return [super writeSelectionToPasteboard:pboard types:types];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard type:(NSString *)type
{
    if (![self selectionContainsRenderedObject]) {
        return [super writeSelectionToPasteboard:pboard type:type];
    }
    NSUInteger objectIndex = NSNotFound;
    OMRenderedObject *single = [self selectedRenderedObject:&objectIndex];
    if ([type isEqualToString:NSStringPboardType]) {
        NSString *text = (single != nil ? [single source] : [[self selectionWithObjectsAsMarkdown] string]);
        return [pboard setString:text forType:NSStringPboardType];
    }
    if ([type isEqualToString:NSRTFPboardType]) {
        NSAttributedString *text = [self selectionWithObjectsAsMarkdown];
        NSData *rtf = [text RTFFromRange:NSMakeRange(0, [text length]) documentAttributes:[NSDictionary dictionary]];
        return rtf != nil && [pboard setData:rtf forType:NSRTFPboardType];
    }
    if ([type isEqualToString:NSTIFFPboardType]) {
        NSImage *image = (single != nil ? [self imageForRenderedObjectAtIndex:objectIndex] : nil);
        NSData *tiff = [image TIFFRepresentation];
        return tiff != nil && [pboard setData:tiff forType:NSTIFFPboardType];
    }
    // RTFD would carry the attachments without their source; skip it.
    if ([type isEqualToString:NSRTFDPboardType]) {
        return NO;
    }
    return [super writeSelectionToPasteboard:pboard type:type];
}

#pragma mark - Context menu

- (NSMenu *)renderedObjectMenuForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSUInteger index = NSNotFound;
    OMRenderedObject *object = [self renderedObjectAtPoint:point characterIndex:&index];
    if (object == nil) {
        return nil;
    }
    _contextObjectIndex = index;
    [_contextObject release];
    _contextObject = [object retain];
    [self setSelectedRange:NSMakeRange(index, 1)];

    NSString *kind = [object kindDisplayName];
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:kind] autorelease];
    [menu setAutoenablesItems:NO];
    NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:[NSString stringWithFormat:@"Copy %@ Source", kind]
                                       action:@selector(copyRenderedObjectSource:)
                                keyEquivalent:@""];
    [item setTarget:self];
    item = (NSMenuItem *)[menu addItemWithTitle:@"Copy as Markdown"
                           action:@selector(copyRenderedObjectMarkdown:)
                    keyEquivalent:@""];
    [item setTarget:self];
    item = (NSMenuItem *)[menu addItemWithTitle:@"Copy Image"
                           action:@selector(copyRenderedObjectImage:)
                    keyEquivalent:@""];
    [item setTarget:self];
    item = (NSMenuItem *)[menu addItemWithTitle:@"Save Image As..."
                           action:@selector(saveRenderedObjectImage:)
                    keyEquivalent:@""];
    [item setTarget:self];
    [menu addItem:[NSMenuItem separatorItem]];
    item = (NSMenuItem *)[menu addItemWithTitle:@"Reveal in Source"
                           action:@selector(revealRenderedObjectSource:)
                    keyEquivalent:@""];
    [item setTarget:self];
    [item setEnabled:([object sourceLineRange].location != NSNotFound &&
                      [[self delegate] respondsToSelector:@selector(textView:revealSourceLineRange:)])];
    return menu;
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = [self renderedObjectMenuForEvent:event];
    return menu != nil ? menu : [super menuForEvent:event];
}

// GNUstep's NSTextView builds its own menu here instead of asking menuForEvent:.
- (void)rightMouseDown:(NSEvent *)event
{
    NSMenu *menu = [self renderedObjectMenuForEvent:event];
    if (menu == nil) {
        [super rightMouseDown:event];
        return;
    }
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

// The object the context menu was opened on; nil if a re-render replaced it.
- (OMRenderedObject *)contextRenderedObject
{
    if (_contextObject == nil || [self renderedObjectAtCharacterIndex:_contextObjectIndex] != _contextObject) {
        return nil;
    }
    return _contextObject;
}

- (void)copyRenderedObjectSource:(id)sender
{
    OMRenderedObject *object = [self contextRenderedObject];
    if (object == nil) {
        return;
    }
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pboard setString:[object source] forType:NSStringPboardType];
}

- (void)copyRenderedObjectMarkdown:(id)sender
{
    OMRenderedObject *object = [self contextRenderedObject];
    if (object == nil) {
        return;
    }
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pboard setString:[object markdown] forType:NSStringPboardType];
}

- (void)copyRenderedObjectImage:(id)sender
{
    NSData *tiff = ([self contextRenderedObject] != nil
                    ? [[self imageForRenderedObjectAtIndex:_contextObjectIndex] TIFFRepresentation]
                    : nil);
    if (tiff == nil) {
        NSBeep();
        return;
    }
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:[NSArray arrayWithObject:NSTIFFPboardType] owner:nil];
    [pboard setData:tiff forType:NSTIFFPboardType];
}

- (void)saveRenderedObjectImage:(id)sender
{
    OMRenderedObject *object = [self contextRenderedObject];
    NSImage *image = [self imageForRenderedObjectAtIndex:_contextObjectIndex];
    NSData *tiff = [image TIFFRepresentation];
    NSBitmapImageRep *bitmap = (tiff != nil ? [NSBitmapImageRep imageRepWithData:tiff] : nil);
    NSData *png = [bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
    if (object == nil || png == nil) {
        NSBeep();
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:[NSString stringWithFormat:@"Save %@ Image", [object kindDisplayName]]];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"png"]];
    [panel setNameFieldStringValue:[[[object kindDisplayName] lowercaseString] stringByAppendingPathExtension:@"png"]];
    if ([panel runModal] != NSFileHandlingPanelOKButton) {
        return;
    }
    NSError *error = nil;
    if (![png writeToURL:[panel URL] options:NSDataWritingAtomic error:&error]) {
        if (error != nil) {
            [[NSAlert alertWithError:error] runModal];
        } else {
            NSBeep();
        }
    }
}

- (void)revealRenderedObjectSource:(id)sender
{
    OMRenderedObject *object = [self contextRenderedObject];
    id delegate = [self delegate];
    if (object == nil || [object sourceLineRange].location == NSNotFound ||
        ![delegate respondsToSelector:@selector(textView:revealSourceLineRange:)]) {
        NSBeep();
        return;
    }
    [delegate textView:self revealSourceLineRange:[object sourceLineRange]];
}

@end
