// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Edit Block (#294, docs/read-edit-design.md): one block of the rendered
// preview is shown as its Markdown source and edited in place. The source
// text stays the only model. Each change in the open block is made at the
// same place in the source, and the source changes nowhere else.

@class OMDBlockEditor;

// Where the source lives. The app applies the change through the source
// editor (so the document is marked edited and Split follows); the tests
// use a plain string.
@protocol OMDBlockEditorSource <NSObject>
- (NSString *)blockEditorSourceString;
// Replace range of the source with string; NO if it couldn't.
- (BOOL)blockEditor:(OMDBlockEditor *)editor
    replaceSourceCharactersInRange:(NSRange)range
                        withString:(NSString *)string;
@end

// Attribute (@YES) on the open block's text in the preview.
extern NSString * const OMDOpenBlockAttributeName;

// The index in the renderer's -editableBlocks of the block whose rendered
// text is at characterIndex (or ends just before it: a caret after a block's
// last character), with that text's range; NSNotFound if there's none.
NSUInteger OMDEditableBlockIndexAtCharacterIndex(NSAttributedString *text,
                                                 NSUInteger characterIndex,
                                                 NSRange *renderedRange);

// Where a caret at renderedOffset in a block's rendered text falls in the
// block's source: the rendered text is aligned with the source, skipping
// the markup the renderer drops (emphasis markers, link destinations,
// entity names, the markers of continuation lines), and the caret goes
// just after the source character of the last rendered character before
// it. A soft line break matches any white space. The result is between 0
// and the source's length.
NSUInteger OMDBlockSourceOffsetForRenderedOffset(NSString *rendered,
                                                 NSString *source,
                                                 NSUInteger renderedOffset);

@interface OMDBlockEditor : NSObject
{
    NSTextStorage *_previewStorage;
    id<OMDBlockEditorSource> _source;
    NSRange _openRange;
    NSRange _sourceRange;
    NSMutableString *_openText;
    NSString *_originalSource;
    BOOL _open;
    BOOL _updatingPreview;
    BOOL _outOfSync;
}

// The preview's text storage is watched for edits while a block is open.
// The source is not retained.
- (instancetype)initWithPreviewStorage:(NSTextStorage *)previewStorage
                                source:(id<OMDBlockEditorSource>)source;

// Replaces renderedRange of the preview with the source's sourceRange,
// drawn with attributes, and opens it. NO (and nothing changes) if a block
// is already open or a range is out of bounds.
- (BOOL)openBlockAtRenderedRange:(NSRange)renderedRange
                     sourceRange:(NSRange)sourceRange
                      attributes:(NSDictionary *)attributes;

// Whether an edit of range in the preview stays inside the open block. A
// range touching either end of it counts, so text can be added at its
// start and end.
- (BOOL)allowsChangeInRange:(NSRange)range;

// Stops mirroring the preview's edits and returns the block's range in the
// source as edited. The caller renders the preview again.
- (NSRange)closeBlock;

@property (nonatomic, readonly, getter=isOpen) BOOL open;
// The open block's range in the preview, and in the source.
@property (nonatomic, readonly) NSRange openRange;
@property (nonatomic, readonly) NSRange sourceRange;
// The block's source when it was opened: putting it back over sourceRange
// undoes every edit of this opening at once.
@property (nonatomic, readonly) NSString *originalSource;
// YES once an edit couldn't be mirrored (an edit outside the block, or the
// source refused it); the caller should close the block and render again.
@property (nonatomic, readonly, getter=isOutOfSync) BOOL outOfSync;

@end
