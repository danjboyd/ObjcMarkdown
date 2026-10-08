// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Posted when a document comes to have unsaved changes or no longer has
// them (an edit, an undo back to the saved text, a save); the object is
// the document.
extern NSString * const OMDMarkdownDocumentEditedStateDidChangeNotification;

// The domain of the errors reading a text file gives.
extern NSString * const OMDTextFileErrorDomain;

// How a document shows: rendered Markdown, or text as it is (code, plain
// text) in a code block.
typedef NS_ENUM(NSInteger, OMDDocumentRenderMode) {
    OMDDocumentRenderModeMarkdown = 0,
    OMDDocumentRenderModeVerbatim = 1
};

// One open document: its text and what was known about it on disk. Each
// has its own undo history, and its unsaved changes follow that history,
// so undoing back to the saved text leaves it unchanged.
@interface OMDMarkdownDocument : NSDocument
{
    NSString *_markdown;
    NSString *_displayTitle;
    BOOL _readOnly;
    OMDDocumentRenderMode _renderMode;
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
@property (nonatomic, assign) OMDDocumentRenderMode renderMode;
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

// The text of the file at path, and how it shows: Markdown for Markdown
// files, else verbatim with the syntax language its extension names.
// Detects the encoding; refuses binary files. renderMode and
// syntaxLanguage may be NULL.
+ (BOOL)readTextFileAtPath:(NSString *)path
                      text:(NSString **)text
                renderMode:(OMDDocumentRenderMode *)renderMode
            syntaxLanguage:(NSString **)syntaxLanguage
                     error:(NSError **)error;

// The name the tab strip shows: the title, else the file's name, else
// "Untitled".
- (NSString *)tabTitle;

// Marks it changed in a way its undo history can't take back (text
// restored from a recovery snapshot, an edit made without undo).
- (void)markChangedOutsideUndo;
// Marks it saved: what it shows is what is on disk.
- (void)markSaved;

@end
