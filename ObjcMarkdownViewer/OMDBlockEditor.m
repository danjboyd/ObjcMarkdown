// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDBlockEditor.h"
#import "OMMarkdownRenderer.h"

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

@implementation OMDBlockEditor

@synthesize open = _open;
@synthesize openRange = _openRange;
@synthesize sourceRange = _sourceRange;
@synthesize outOfSync = _outOfSync;

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
    NSMutableDictionary *blockAttributes = [NSMutableDictionary dictionaryWithDictionary:(attributes != nil ? attributes : [NSDictionary dictionary])];
    [blockAttributes setObject:[NSNumber numberWithBool:YES] forKey:OMDOpenBlockAttributeName];
    NSAttributedString *block = [[[NSAttributedString alloc] initWithString:[sourceString substringWithRange:sourceRange]
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
    if (oldSpan.length > 0 || newSpan.length > 0) {
        NSRange sourceReplaced = NSMakeRange(_sourceRange.location + oldSpan.location, oldSpan.length);
        if (![_source blockEditor:self
            replaceSourceCharactersInRange:sourceReplaced
                                withString:[now substringWithRange:newSpan]]) {
            _outOfSync = YES;
            return;
        }
    }
    [_openText setString:now];
    _openRange.length = nowLength;
    _sourceRange.length = (NSUInteger)((NSInteger)_sourceRange.length + ((NSInteger)nowLength - (NSInteger)oldLength));
}

@end
