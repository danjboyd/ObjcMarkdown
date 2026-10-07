// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDMarkdownDocument.h"
#import "OMDTextFileSupport.h"

NSString * const OMDMarkdownDocumentEditedStateDidChangeNotification = @"OMDMarkdownDocumentEditedStateDidChange";

#if defined(GNUSTEP)
// GNUstep's NSDocument counts a change as each undo group closes.
@interface NSDocument (OMDUndoGroupCounting)
- (void)_changeWasDone:(NSNotification *)notification;
@end
#endif

@implementation OMDMarkdownDocument

#if defined(GNUSTEP)
// An edit made in an undo group (the formatting commands) sits in the
// group the run loop opens around each event, and GNUstep counted both as
// they closed: one edit, two changes, and Undo didn't bring the document
// back to unchanged. Count the outermost group only, as macOS does.
- (void)_changeWasDone:(NSNotification *)notification
{
    if ([[self undoManager] groupingLevel] > 1) {
        return;
    }
    [super _changeWasDone:notification];
}
#endif

@synthesize markdown = _markdown;
@synthesize displayTitle = _displayTitle;
@synthesize readOnly = _readOnly;
@synthesize renderMode = _renderMode;
@synthesize syntaxLanguage = _syntaxLanguage;
@synthesize remoteURL = _remoteURL;
@synthesize loadedDiskFingerprint = _loadedDiskFingerprint;
@synthesize observedDiskFingerprint = _observedDiskFingerprint;
@synthesize suppressedDiskFingerprint = _suppressedDiskFingerprint;
@synthesize imageFingerprints = _imageFingerprints;
@synthesize suppressedImageFingerprints = _suppressedImageFingerprints;
@synthesize imageMarkdown = _imageMarkdown;
@synthesize imageSourcePath = _imageSourcePath;

- (void)dealloc
{
    [_markdown release];
    [_displayTitle release];
    [_syntaxLanguage release];
    [_remoteURL release];
    [_loadedDiskFingerprint release];
    [_observedDiskFingerprint release];
    [_suppressedDiskFingerprint release];
    [_imageFingerprints release];
    [_suppressedImageFingerprints release];
    [_imageMarkdown release];
    [_imageSourcePath release];
    [super dealloc];
}

- (NSString *)sourcePath
{
    NSURL *url = [self fileURL];
    return [url isFileURL] ? [url path] : nil;
}

- (void)setSourcePath:(NSString *)sourcePath
{
    NSString *path = OMDTrimmedString(sourcePath);
    NSString *current = [self sourcePath];
    if ([path length] == 0 ? current == nil : [path isEqualToString:current]) {
        return;
    }
    [self setFileURL:([path length] > 0 ? [NSURL fileURLWithPath:path] : nil)];
}

- (NSString *)tabTitle
{
    if ([_displayTitle length] > 0) {
        return _displayTitle;
    }
    NSString *path = [self sourcePath];
    return [path length] > 0 ? [path lastPathComponent] : @"Untitled";
}

- (void)updateChangeCount:(NSDocumentChangeType)change
{
    BOOL wasEdited = [self isDocumentEdited];
    [super updateChangeCount:change];
    if ([self isDocumentEdited] != wasEdited) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OMDMarkdownDocumentEditedStateDidChangeNotification
                                                            object:self];
    }
}

- (void)markChangedOutsideUndo
{
    if (![self isDocumentEdited]) {
        [self updateChangeCount:NSChangeReadOtherContents];
    }
}

- (void)markSaved
{
    [self updateChangeCount:NSChangeCleared];
}

@end
