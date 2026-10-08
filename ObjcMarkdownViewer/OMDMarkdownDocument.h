// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Posted when a document comes to have unsaved changes or no longer has
// them (an edit, an undo back to the saved text, a save); the object is
// the document.
extern NSString * const OMDMarkdownDocumentEditedStateDidChangeNotification;

// One open document: its text and what was known about it on disk. Each
// has its own undo history, and its unsaved changes follow that history,
// so undoing back to the saved text leaves it unchanged.
@interface OMDMarkdownDocument : NSDocument
{
    NSString *_markdown;
    NSString *_displayTitle;
    BOOL _readOnly;
    NSInteger _renderMode;
    NSString *_syntaxLanguage;
    NSString *_remoteURL;
    NSString *_loadedDiskFingerprint;
    NSString *_observedDiskFingerprint;
    NSString *_suppressedDiskFingerprint;
    NSDictionary *_imageFingerprints;
    NSDictionary *_suppressedImageFingerprints;
    NSString *_imageMarkdown;
    NSString *_imageSourcePath;
}

// The text as last shown (the editor's, for the document on show).
@property (nonatomic, copy) NSString *markdown;
// The file it was opened from or saved to, or nil (untitled, or from the
// web). The same as -fileURL's path.
@property (nonatomic, copy) NSString *sourcePath;
// What the tab and window show, when not the file's name.
@property (nonatomic, copy) NSString *displayTitle;
@property (nonatomic, assign) BOOL readOnly;
// An OMDDocumentRenderMode.
@property (nonatomic, assign) NSInteger renderMode;
@property (nonatomic, copy) NSString *syntaxLanguage;
// A document opened from the web: its raw address.
@property (nonatomic, copy) NSString *remoteURL;

// The file as loaded, as last seen on disk, and a change the reader chose
// to keep their text over (OMDDiskFingerprintForFileAttributes).
@property (nonatomic, copy) NSString *loadedDiskFingerprint;
@property (nonatomic, copy) NSString *observedDiskFingerprint;
@property (nonatomic, copy) NSString *suppressedDiskFingerprint;
// The local images it shows, as loaded, and a change kept over; with the
// text and path they were found for.
@property (nonatomic, copy) NSDictionary *imageFingerprints;
@property (nonatomic, copy) NSDictionary *suppressedImageFingerprints;
@property (nonatomic, copy) NSString *imageMarkdown;
@property (nonatomic, copy) NSString *imageSourcePath;

// The name the tab strip shows: the title, else the file's name, else
// "Untitled".
- (NSString *)tabTitle;

// Marks it changed in a way its undo history can't take back (text
// restored from a recovery snapshot, an edit made without undo).
- (void)markChangedOutsideUndo;
// Marks it saved: what it shows is what is on disk.
- (void)markSaved;

@end
