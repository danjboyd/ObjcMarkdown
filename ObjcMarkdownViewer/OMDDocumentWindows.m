// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDDocumentWindows.h"

#if !defined(GNUSTEP)
#import "OMDAppDelegate.h"
#import "OMDDocumentConverter.h"
#import "OMDDocumentTabsController.h"
#import "OMDTextFileSupport.h"

NSString * const OMDMarkdownDocumentDidSaveNotification = @"OMDMarkdownDocumentDidSave";
NSString * const OMDMarkdownDocumentDidRevertNotification = @"OMDMarkdownDocumentDidRevert";

static NSString * const OMDMarkdownTypeName = @"net.daringfireball.markdown";
static NSString * const OMDPlainTextTypeName = @"public.plain-text";
static NSString * const OMDDocumentTabbingIdentifier = @"MarkdownViewerDocument";

// The window controller's own methods this file uses.
@interface OMDWindowController (OMDDocumentWindowsPrivate)
- (void)setupWindow;
- (void)presentWindowIfNeeded;
- (void)schedulePostPresentationSetupIfNeeded;
- (void)registerAsSecondaryWindow;
- (OMDMarkdownDocument *)currentDocument;
- (void)captureCurrentStateIntoSelectedTab;
- (void)installDocumentTabRecord:(OMDMarkdownDocument *)tab
                         inNewTab:(BOOL)inNewTab
                    resetViewport:(BOOL)resetViewport;
- (void)applyDocumentTabRecord:(OMDMarkdownDocument *)tabRecord;
- (BOOL)importDocumentAtPath:(NSString *)path;
- (void)updateWindowTitle;
- (void)setViewerMode:(NSInteger)mode persistPreference:(BOOL)persistPreference;
@end

#pragma mark - Document controller

@implementation OMDDocumentController

- (void)openDocumentWithContentsOfURL:(NSURL *)url
                              display:(BOOL)displayDocument
                    completionHandler:(void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error))completionHandler
{
    NSString *extension = [[url pathExtension] lowercaseString];
    if ([url isFileURL] && [OMDDocumentConverter isSupportedExtension:extension]) {
        // Word, RTF, ODT, HTML: a new Markdown document made from it, which
        // Save puts where the reader chooses.
        OMDWindowController *controller = [(OMDAppDelegate *)[NSApp delegate] activeWindowController];
        if ([controller showsArchitectureDocument] || [[controller mainWindow] isVisible] == NO) {
            controller = [OMDWindowController documentWindowController];
        }
        [controller importDocumentAtPath:[url path]];
        if (completionHandler != nil) {
            completionHandler([controller showsArchitectureDocument] ? [[controller documentWindowController] document] : nil,
                              NO, nil);
        }
        return;
    }
    [super openDocumentWithContentsOfURL:url display:displayDocument completionHandler:completionHandler];
}

@end

#pragma mark - The window's NSWindowController

@implementation OMDDocumentWindowController

- (instancetype)initWithContentController:(OMDWindowController *)contentController
{
    self = [super initWithWindow:[contentController mainWindow]];
    if (self != nil) {
        // Not retained: the content controller keeps this one.
        _contentController = contentController;
    }
    return self;
}

- (OMDWindowController *)contentController
{
    return _contentController;
}

// The window's title is the document's name; for a document from the web,
// the title it was given.
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
    return displayName;
}

@end

#pragma mark - Documents

@implementation OMDMarkdownDocument (OMDDocumentWindows)

+ (BOOL)autosavesInPlace
{
    return YES;
}

- (void)makeWindowControllers
{
    // The window in front if it shows nothing yet (the window the app
    // starts with), else a new one, which joins its tabs.
    OMDWindowController *controller = [(OMDAppDelegate *)[NSApp delegate] activeWindowController];
    if (controller == nil || [controller showsArchitectureDocument] ||
        [[controller mainWindow] isVisible] == NO || [[controller currentDocument] markdown] != nil) {
        controller = [OMDWindowController documentWindowController];
    }
    [controller showDocumentFromDocumentController:self];
}

- (NSString *)displayName
{
    if ([self fileURL] == nil && [[self displayTitle] length] > 0) {
        return [self displayTitle];
    }
    return [super displayName];
}

- (void)saveToURL:(NSURL *)url
           ofType:(NSString *)typeName
 forSaveOperation:(NSSaveOperationType)saveOperation
completionHandler:(void (^)(NSError *errorOrNil))completionHandler
{
    void (^handler)(NSError *) = [[completionHandler copy] autorelease];
    [super saveToURL:url ofType:typeName forSaveOperation:saveOperation completionHandler:^(NSError *error) {
        if (error == nil) {
            [[NSNotificationCenter defaultCenter] postNotificationName:OMDMarkdownDocumentDidSaveNotification
                                                                object:self];
        }
        if (handler != nil) {
            handler(error);
        }
    }];
}

- (BOOL)revertToContentsOfURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
    if (![super revertToContentsOfURL:url ofType:typeName error:error]) {
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:OMDMarkdownDocumentDidRevertNotification
                                                        object:self];
    return YES;
}

@end

#pragma mark - The window controller's side

@implementation OMDWindowController (OMDDocumentWindows)

+ (OMDWindowController *)documentWindowController
{
    OMDWindowController *controller = [[OMDWindowController alloc] init];
    [controller setupWindow];
    [controller presentWindowIfNeeded];
    [controller schedulePostPresentationSetupIfNeeded];
    [controller registerAsSecondaryWindow];
    return [controller autorelease];
}

- (void)setUpDocumentWindow
{
    if (_documentWindowController != nil || _window == nil) {
        return;
    }
    _documentWindowController = [[OMDDocumentWindowController alloc] initWithContentController:self];
    // Documents open as tabs of the window in front.
    [_window setTabbingMode:NSWindowTabbingModePreferred];
    [_window setTabbingIdentifier:OMDDocumentTabbingIdentifier];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(architectureDocumentDidSave:)
                   name:OMDMarkdownDocumentDidSaveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(architectureDocumentDidRevert:)
                   name:OMDMarkdownDocumentDidRevertNotification
                 object:nil];
}

- (OMDDocumentWindowController *)documentWindowController
{
    return (OMDDocumentWindowController *)_documentWindowController;
}

- (BOOL)showsArchitectureDocument
{
    return [[self documentWindowController] document] != nil;
}

- (BOOL)prepareToShowDocument:(OMDMarkdownDocument *)document inNewTab:(BOOL)inNewTab
{
    OMDMarkdownDocument *current = (OMDMarkdownDocument *)[[self documentWindowController] document];
    if (current == nil) {
        return NO;
    }
    // A new tab is a new window, which the system groups with this one; so
    // is a document in place of one with unsaved changes and no file yet,
    // which can't be put away without asking.
    if (inNewTab || ([current fileURL] == nil && [current isDocumentEdited])) {
        OMDWindowController *controller = [OMDWindowController documentWindowController];
        [controller installDocumentTabRecord:document inNewTab:NO resetViewport:YES];
        return YES;
    }

    // In place: the document on show is saved (in place, as autosave does)
    // and closed.
    [self captureCurrentStateIntoSelectedTab];
    [current retain];
    [current removeWindowController:[self documentWindowController]];
    if ([current isDocumentEdited] && [current fileURL] != nil) {
        [current autosaveWithImplicitCancellability:NO completionHandler:^(NSError *error) {
            if (error != nil) {
                NSLog(@"MarkdownViewer: saving %@ before closing it failed: %@", [current displayName], error);
            }
            [current close];
            [current release];
        }];
    } else {
        [current close];
        [current release];
    }
    return NO;
}

- (void)adoptShownDocument:(OMDMarkdownDocument *)document
{
    if (document == nil || [document windowControllers] == nil ||
        [[document windowControllers] containsObject:[self documentWindowController]]) {
        return;
    }
    NSString *path = [document sourcePath];
    if ([document fileType] == nil) {
        [document setFileType:([document renderMode] == OMDDocumentRenderModeVerbatim ? OMDPlainTextTypeName
                                                                                      : OMDMarkdownTypeName)];
    }
    if ([path length] > 0) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        [document setFileModificationDate:[attributes fileModificationDate]];
    }
    NSDocumentController *documents = [NSDocumentController sharedDocumentController];
    if (![[documents documents] containsObject:document]) {
        [documents addDocument:document];
    }
    [document addWindowController:[self documentWindowController]];
    [self updateWindowTitle];
}

- (BOOL)showOpenDocumentAtPath:(NSString *)path
{
    if ([path length] == 0) {
        return NO;
    }
    NSDocument *open = [[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:path]];
    if (open == nil) {
        return NO;
    }
    [open showWindows];
    return YES;
}

- (void)showDocumentFromDocumentController:(OMDMarkdownDocument *)document
{
    [self installDocumentTabRecord:document inNewTab:NO resetViewport:YES];
    if ([document fileURL] == nil && [[document markdown] length] == 0) {
        // File > New: an empty document to write in.
        [self setViewerMode:1 persistPreference:NO];
    }
    [self presentWindowIfNeeded];
}

- (BOOL)architectureDocumentWindowShouldClose
{
    if (_architectureCloseApproved) {
        return YES;
    }
    NSDocument *document = [[self documentWindowController] document];
    [self captureCurrentStateIntoSelectedTab];
    [document shouldCloseWindowController:[self documentWindowController]
                                 delegate:self
                      shouldCloseSelector:@selector(architectureDocument:shouldClose:contextInfo:)
                              contextInfo:NULL];
    return NO;
}

- (void)architectureDocument:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
{
    (void)contextInfo;
    if (!shouldClose) {
        return;
    }
    [document retain];
    _architectureCloseApproved = YES;
    [_window performClose:nil];
    _architectureCloseApproved = NO;
    if ([[[NSDocumentController sharedDocumentController] documents] containsObject:document]) {
        [document close];
    }
    [document release];
}

- (void)revertArchitectureDocumentQuietly
{
    NSDocument *document = [self currentDocument];
    NSError *error = nil;
    if (![document revertToContentsOfURL:[document fileURL] ofType:[document fileType] error:&error]) {
        NSLog(@"MarkdownViewer: reading %@ again failed: %@", [document displayName], error);
    }
}

// Saved (by Save, Duplicate, Rename, Move To or autosave): the window
// follows the file.
- (void)architectureDocumentDidSave:(NSNotification *)notification
{
    if ([notification object] != [self currentDocument]) {
        return;
    }
    OMDMarkdownDocument *document = [notification object];
    NSString *path = [document sourcePath];
    NSString *fingerprint = nil;
    if ([path length] > 0) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        fingerprint = attributes != nil ? OMDDiskFingerprintForFileAttributes(attributes) : nil;
    }
    [document setLoadedDiskFingerprint:fingerprint];
    [document setObservedDiskFingerprint:fingerprint];
    [document setSuppressedDiskFingerprint:nil];
    if (![path isEqualToString:_currentPath]) {
        // Renamed, moved or saved somewhere new: show it from there.
        [self applyDocumentTabRecord:document];
    } else {
        [self updateWindowTitle];
    }
}

// Read again (Revert To, or the file changed in another app while it had
// no unsaved changes): show what was read.
- (void)architectureDocumentDidRevert:(NSNotification *)notification
{
    if ([notification object] != [self currentDocument]) {
        return;
    }
    [self applyDocumentTabRecord:[notification object]];
}

@end
#endif
