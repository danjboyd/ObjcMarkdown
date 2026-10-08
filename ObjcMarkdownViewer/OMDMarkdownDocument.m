// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDMarkdownDocument.h"
#import "OMDTextFileSupport.h"

NSString * const OMDMarkdownDocumentEditedStateDidChangeNotification = @"OMDMarkdownDocumentEditedStateDidChange";
NSString * const OMDTextFileErrorDomain = @"OMDTextFileErrorDomain";

static NSError *OMDTextFileError(NSInteger code, NSString *description)
{
    return [NSError errorWithDomain:OMDTextFileErrorDomain
                               code:code
                           userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

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

+ (BOOL)readTextFileAtPath:(NSString *)path
                      text:(NSString **)text
                renderMode:(OMDDocumentRenderMode *)renderMode
            syntaxLanguage:(NSString **)syntaxLanguage
                     error:(NSError **)error
{
    NSError *failure = nil;
    NSString *decoded = nil;
    if ([path length] == 0) {
        failure = OMDTextFileError(1, @"Missing file path.");
    } else {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data == nil) {
            failure = OMDTextFileError(4, @"Unable to read file data.");
        } else if (OMDDataAppearsBinary(data)) {
            failure = OMDTextFileError(2, @"This file appears to be binary and cannot be previewed as text.");
        } else {
            decoded = OMDDecodeTextFromData(data, NULL);
            if (decoded == nil) {
                failure = OMDTextFileError(3, @"Unable to decode this file as text.");
            }
        }
    }
    if (failure != nil) {
        if (error != NULL) {
            *error = failure;
        }
        return NO;
    }

    NSString *extension = [[path pathExtension] lowercaseString];
    BOOL markdown = OMDIsMarkdownExtension(extension);
    if (text != NULL) {
        *text = decoded;
    }
    if (renderMode != NULL) {
        *renderMode = markdown ? OMDDocumentRenderModeMarkdown : OMDDocumentRenderModeVerbatim;
    }
    if (syntaxLanguage != NULL) {
        *syntaxLanguage = markdown ? nil : OMDVerbatimSyntaxTokenForExtension(extension);
    }
    return YES;
}

- (NSString *)tabTitle
{
    if ([_displayTitle length] > 0) {
        return _displayTitle;
    }
    NSString *path = [self sourcePath];
    return [path length] > 0 ? [path lastPathComponent] : @"Untitled";
}

// NSDocument's reading: a text or Markdown file. (Word, RTF, ODT and HTML
// are imported as new documents, not read as themselves.)
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    NSString *text = nil;
    OMDDocumentRenderMode mode = OMDDocumentRenderModeMarkdown;
    NSString *syntax = nil;
    if (![url isFileURL] ||
        ![[self class] readTextFileAtPath:[url path] text:&text renderMode:&mode syntaxLanguage:&syntax error:error]) {
        return NO;
    }
    [self setMarkdown:text];
    [self setRenderMode:mode];
    [self setSyntaxLanguage:syntax];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL];
    NSString *fingerprint = attributes != nil ? OMDDiskFingerprintForFileAttributes(attributes) : nil;
    [self setLoadedDiskFingerprint:fingerprint];
    [self setObservedDiskFingerprint:fingerprint];
    [self setSuppressedDiskFingerprint:nil];
    return YES;
}

// NSDocument's writing: the text as UTF-8.
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    (void)error;
    return [(_markdown != nil ? _markdown : @"") dataUsingEncoding:NSUTF8StringEncoding];
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
