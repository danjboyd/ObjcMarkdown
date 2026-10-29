// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareExporter.h"
#import "OMDShareBundle.h"
#import "OMDDocumentConverter.h"

#include <dispatch/dispatch.h>

#include <errno.h>
#include <signal.h>
#include <unistd.h>
#if defined(_WIN32)
#include <windows.h>
#endif

NSString * const OMDShareErrorDomain = @"OMDShareErrorDomain";

// A launch's directory is "<pid>-<start time>", so a sweep can tell
// whether the launch that made it is still running.
static NSString *OMDShareLaunchDirectoryName(void)
{
    static NSString *name = nil;
    if (name == nil) {
        name = [[NSString alloc] initWithFormat:@"%d-%.0f",
                                                (int)getpid(),
                                                [[NSDate date] timeIntervalSince1970]];
    }
    return name;
}

static NSError *OMDShareError(OMDShareErrorCode code, NSString *description)
{
    NSDictionary *info = [NSDictionary dictionaryWithObject:description
                                                     forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:OMDShareErrorDomain code:code userInfo:info];
}

static BOOL OMDShareCreatePrivateDirectory(NSString *path)
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0700]
                                                           forKey:NSFilePosixPermissions];
    return [[NSFileManager defaultManager] createDirectoryAtPath:path
                                     withIntermediateDirectories:YES
                                                      attributes:attributes
                                                           error:NULL];
}

// Whether the launch that named a directory "<pid>-..." is still running.
static BOOL OMDShareLaunchIsRunning(NSString *directoryName)
{
    NSRange dash = [directoryName rangeOfString:@"-"];
    if (dash.location == NSNotFound || dash.location == 0) {
        return NO;
    }
    int pid = [[directoryName substringToIndex:dash.location] intValue];
    if (pid <= 0) {
        return NO;
    }
#if defined(_WIN32)
    // Windows reuses process IDs soon, so the process must also have
    // started before the directory was named (the time after the dash).
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
    if (process == NULL) {
        return GetLastError() == ERROR_ACCESS_DENIED;
    }
    FILETIME created, exited, kernel, user;
    DWORD exitCode = 0;
    BOOL running = (GetExitCodeProcess(process, &exitCode) && exitCode == STILL_ACTIVE);
    if (running && GetProcessTimes(process, &created, &exited, &kernel, &user)) {
        ULARGE_INTEGER ticks;
        ticks.LowPart = created.dwLowDateTime;
        ticks.HighPart = created.dwHighDateTime;
        // FILETIME counts 100 ns from 1601; the name counts seconds from 1970.
        double startedAt = (double)(ticks.QuadPart / 10000000ULL) - 11644473600.0;
        double namedAt = [[directoryName substringFromIndex:dash.location + 1] doubleValue];
        if (namedAt > 0.0 && startedAt > namedAt + 1.0) {
            running = NO;
        }
    }
    CloseHandle(process);
    return running;
#else
    return kill((pid_t)pid, 0) == 0 || errno == EPERM;
#endif
}

@implementation OMDShareExporter

+ (NSString *)fileExtensionForFormat:(OMDShareFormat)format
{
    switch (format) {
    case OMDShareFormatPDF:
        return @"pdf";
    case OMDShareFormatWord:
        return @"docx";
    case OMDShareFormatMarkdown:
        return @"md";
    case OMDShareFormatHTML:
        return @"html";
    }
    return @"pdf";
}

+ (NSString *)displayNameForFormat:(OMDShareFormat)format
{
    switch (format) {
    case OMDShareFormatPDF:
        return @"PDF";
    case OMDShareFormatWord:
        return @"Word Document";
    case OMDShareFormatMarkdown:
        return @"Markdown File";
    case OMDShareFormatHTML:
        return @"HTML";
    }
    return @"PDF";
}

+ (BOOL)formatNeedsConverter:(OMDShareFormat)format
{
    return format == OMDShareFormatWord || format == OMDShareFormatHTML;
}

+ (NSString *)safeFileBaseName:(NSString *)name
{
    // Characters Windows, macOS or Linux refuse in a file name, and
    // control characters, become "-". Leading and trailing dots and spaces
    // go (Windows drops them).
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSMutableString *safe = [NSMutableString string];
    NSUInteger length = [name length];
    NSUInteger index = 0;
    for (index = 0; index < length; index++) {
        unichar c = [name characterAtIndex:index];
        if (c < 0x20 || c == 0x7f || [unsafe characterIsMember:c]) {
            [safe appendString:@"-"];
        } else {
            [safe appendFormat:@"%C", c];
        }
    }
    NSString *trimmed = [safe stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@". \t"]];
    if ([trimmed length] > 120) {
        trimmed = [trimmed substringToIndex:120];
    }
    return [trimmed length] > 0 ? trimmed : @"Document";
}

+ (NSString *)temporaryRootDirectoryInFlatpak:(BOOL)inFlatpak environment:(NSDictionary *)environment
{
    if (inFlatpak) {
        NSString *cache = [environment objectForKey:@"XDG_CACHE_HOME"];
        if ([cache length] == 0) {
            cache = [NSHomeDirectory() stringByAppendingPathComponent:@".cache"];
        }
        return [cache stringByAppendingPathComponent:@"MarkdownViewer-share"];
    }
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"MarkdownViewer-share"];
}

+ (NSString *)temporaryRootDirectory
{
    BOOL inFlatpak = [[NSFileManager defaultManager] fileExistsAtPath:@"/.flatpak-info"];
    return [self temporaryRootDirectoryInFlatpak:inFlatpak
                                     environment:[[NSProcessInfo processInfo] environment]];
}

+ (NSString *)launchTemporaryDirectory
{
    NSString *path = [[self temporaryRootDirectory] stringByAppendingPathComponent:OMDShareLaunchDirectoryName()];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
        return path;
    }
    OMDShareCreatePrivateDirectory([self temporaryRootDirectory]);
    return OMDShareCreatePrivateDirectory(path) ? path : nil;
}

+ (void)sweepStaleTemporaryDirectories
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *root = [self temporaryRootDirectory];
    NSArray *names = [manager contentsOfDirectoryAtPath:root error:NULL];
    NSString *current = OMDShareLaunchDirectoryName();
    NSDate *dayAgo = [NSDate dateWithTimeIntervalSinceNow:-24.0 * 60.0 * 60.0];
    for (NSString *name in names) {
        if ([name isEqualToString:current]) {
            continue;
        }
        NSString *path = [root stringByAppendingPathComponent:name];
        NSDate *modified = [[manager attributesOfItemAtPath:path error:NULL] fileModificationDate];
        BOOL old = (modified != nil && [modified compare:dayAgo] == NSOrderedAscending);
        if (old || !OMDShareLaunchIsRunning(name)) {
            [manager removeItemAtPath:path error:NULL];
        }
    }
}

- (instancetype)initWithSource:(id<OMDShareSource>)source
{
    self = [super init];
    if (self != nil) {
        _source = source;
    }
    return self;
}

// A new directory for one share, so its file can keep the document's name
// however often it is shared.
- (NSString *)newShareDirectory
{
    NSString *launch = [[self class] launchTemporaryDirectory];
    if (launch == nil) {
        return nil;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSUInteger attempt = 0;
    for (attempt = 1; attempt < 10000; attempt++) {
        NSString *path = [launch stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%lu", (unsigned long)attempt]];
        if (![manager fileExistsAtPath:path] && OMDShareCreatePrivateDirectory(path)) {
            return path;
        }
    }
    return nil;
}

- (BOOL)hasSelection
{
    return [_source respondsToSelector:@selector(shareSelectedSourceText)] &&
           [_source shareSelectedSourceText] != nil;
}

// The text a share takes: the document's or the selection's, as source or
// as Markdown. Nil with selectionOnly and nothing selected.
- (NSString *)sourceTextForSelection:(BOOL)selectionOnly
{
    if (!selectionOnly) {
        return [_source shareSourceText];
    }
    return [self hasSelection] ? [_source shareSelectedSourceText] : nil;
}

- (NSString *)markdownTextForSelection:(BOOL)selectionOnly
{
    if (!selectionOnly) {
        return [_source shareMarkdownText];
    }
    return [_source respondsToSelector:@selector(shareSelectedMarkdownText)] ? [_source shareSelectedMarkdownText] : nil;
}

- (NSAttributedString *)renderedTextForSelection:(BOOL)selectionOnly
{
    if (!selectionOnly) {
        return [_source shareRenderedText];
    }
    NSString *markdown = [self markdownTextForSelection:YES];
    if (markdown == nil || ![_source respondsToSelector:@selector(shareRenderedTextForMarkdown:)]) {
        return nil;
    }
    return [_source shareRenderedTextForMarkdown:markdown];
}

- (BOOL)writePDFToPath:(NSString *)path selectionOnly:(BOOL)selectionOnly
{
    if (!selectionOnly) {
        return [_source shareWritePDFToPath:path];
    }
    NSString *markdown = [self markdownTextForSelection:YES];
    return markdown != nil &&
           [_source respondsToSelector:@selector(shareWritePDFForMarkdown:toPath:)] &&
           [_source shareWritePDFForMarkdown:markdown toPath:path];
}

static NSError *OMDShareMissingTextError(BOOL selectionOnly)
{
    return selectionOnly ? OMDShareError(OMDShareErrorNoDocument, @"Select some of the document first.")
                         : OMDShareError(OMDShareErrorNoDocument, @"Open or import a document first.");
}

- (OMDShareItem *)shareItemForFormat:(OMDShareFormat)format error:(NSError **)error
{
    return [self shareItemForFormat:format selectionOnly:NO error:error];
}

- (OMDShareItem *)shareItemForFormat:(OMDShareFormat)format
                       selectionOnly:(BOOL)selectionOnly
                               error:(NSError **)error
{
    NSString *sourceText = [self sourceTextForSelection:selectionOnly];
    if (sourceText == nil) {
        if (error != NULL) {
            *error = OMDShareMissingTextError(selectionOnly);
        }
        return nil;
    }
    OMDDocumentConverter *converter = nil;
    if ([[self class] formatNeedsConverter:format]) {
        converter = [_source documentConverter];
        if (converter == nil) {
            if (error != NULL) {
                *error = OMDShareError(OMDShareErrorConverterUnavailable,
                                       [OMDDocumentConverter missingBackendInstallMessage]);
            }
            return nil;
        }
    }

    NSString *directory = [self newShareDirectory];
    if (directory == nil) {
        if (error != NULL) {
            *error = OMDShareError(OMDShareErrorTemporaryDirectory,
                                   @"Couldn't make a temporary folder for the shared file.");
        }
        return nil;
    }

    NSString *title = [[self class] safeFileBaseName:[_source shareBaseName]];
    NSString *extension = [[self class] fileExtensionForFormat:format];
    if (format == OMDShareFormatMarkdown) {
        NSString *sourceExtension = [_source shareSourceExtension];
        if ([sourceExtension length] > 0) {
            extension = sourceExtension;
        }
    }
    NSString *path = [directory stringByAppendingPathComponent:
        [title stringByAppendingPathExtension:extension]];

    BOOL written = NO;
    NSError *writeError = nil;
    switch (format) {
    case OMDShareFormatMarkdown:
        written = [sourceText writeToFile:path
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&writeError];
        break;
    case OMDShareFormatPDF:
        written = [self writePDFToPath:path selectionOnly:selectionOnly];
        break;
    case OMDShareFormatWord:
    case OMDShareFormatHTML:
        written = [converter exportMarkdown:[self markdownTextForSelection:selectionOnly]
                                     toPath:path
                          resourceDirectory:[_source shareResourceDirectory]
                                      error:&writeError];
        break;
    }
    if (!written || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
        if (error != NULL) {
            *error = writeError != nil
                ? writeError
                : OMDShareError(OMDShareErrorWriteFailed,
                                [NSString stringWithFormat:@"The %@ could not be created.",
                                                           [[self class] displayNameForFormat:format]]);
        }
        return nil;
    }

    OMDShareItem *item = [[[OMDShareItem alloc] initWithTitle:title
                                                       format:format
                                                      fileURL:[NSURL fileURLWithPath:path]
                                                 renderedText:[self renderedTextForSelection:selectionOnly]] autorelease];
    if (format == OMDShareFormatMarkdown && !selectionOnly &&
        [_source respondsToSelector:@selector(shareDocumentPath)]) {
        NSString *documentPath = [_source shareDocumentPath];
        // An imported document's file isn't the Markdown shared.
        if ([documentPath length] > 0 && [[documentPath pathExtension] isEqualToString:extension]) {
            [item setDocumentURL:[NSURL fileURLWithPath:documentPath]];
        }
    }
    return item;
}

- (OMDShareItem *)bundleShareItemWithError:(NSError **)error
{
    NSString *sourceText = [_source shareSourceText];
    if (sourceText == nil) {
        if (error != NULL) {
            *error = OMDShareError(OMDShareErrorNoDocument, @"Open or import a document first.");
        }
        return nil;
    }
    NSString *directory = [self newShareDirectory];
    if (directory == nil) {
        if (error != NULL) {
            *error = OMDShareError(OMDShareErrorTemporaryDirectory,
                                   @"Couldn't make a temporary folder for the shared file.");
        }
        return nil;
    }
    NSString *title = [[self class] safeFileBaseName:[_source shareBaseName]];
    NSString *path = [directory stringByAppendingPathComponent:[title stringByAppendingPathExtension:@"zip"]];
    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *contents = [NSMutableArray array];
    OMDShareBundleEntries(sourceText, [_source shareResourceDirectory], title, names, contents);
    if (!OMDShareWriteZip(path, names, contents)) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
        if (error != NULL) {
            *error = OMDShareError(OMDShareErrorWriteFailed, @"The .zip could not be created.");
        }
        return nil;
    }
    return [[[OMDShareItem alloc] initWithTitle:title
                                         format:OMDShareFormatMarkdown
                                        fileURL:[NSURL fileURLWithPath:path]
                                   renderedText:nil] autorelease];
}

- (void)shareItemForFormat:(OMDShareFormat)format
                completion:(void (^)(OMDShareItem *item, NSError *error))completion
{
    [self shareItemForFormat:format selectionOnly:NO completion:completion];
}

- (void)shareItemForFormat:(OMDShareFormat)format
             selectionOnly:(BOOL)selectionOnly
                completion:(void (^)(OMDShareItem *item, NSError *error))completion
{
    if (![[self class] formatNeedsConverter:format]) {
        NSError *error = nil;
        OMDShareItem *item = [self shareItemForFormat:format selectionOnly:selectionOnly error:&error];
        completion(item, error);
        return;
    }
    // Everything from the document and the window, read here on the main
    // thread; only Pandoc runs on the queue.
    NSString *markdown = [self markdownTextForSelection:selectionOnly];
    if (markdown == nil) {
        completion(nil, OMDShareMissingTextError(selectionOnly));
        return;
    }
    OMDDocumentConverter *converter = [_source documentConverter];
    if (converter == nil) {
        completion(nil, OMDShareError(OMDShareErrorConverterUnavailable,
                                      [OMDDocumentConverter missingBackendInstallMessage]));
        return;
    }
    NSString *directory = [self newShareDirectory];
    if (directory == nil) {
        completion(nil, OMDShareError(OMDShareErrorTemporaryDirectory,
                                      @"Couldn't make a temporary folder for the shared file."));
        return;
    }
    NSString *title = [[self class] safeFileBaseName:[_source shareBaseName]];
    NSString *path = [directory stringByAppendingPathComponent:
        [title stringByAppendingPathExtension:[[self class] fileExtensionForFormat:format]]];
    NSString *resourceDirectory = [_source shareResourceDirectory];
    NSAttributedString *rendered = [self renderedTextForSelection:selectionOnly];
    NSString *failure = [NSString stringWithFormat:@"The %@ could not be created.",
                                                   [[self class] displayNameForFormat:format]];
    void (^done)(OMDShareItem *, NSError *) = [completion copy];

    [markdown retain];
    [converter retain];
    [directory retain];
    [title retain];
    [path retain];
    [resourceDirectory retain];
    [rendered retain];
    [failure retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *writeError = nil;
        BOOL written = [converter exportMarkdown:markdown
                                          toPath:path
                               resourceDirectory:resourceDirectory
                                           error:&writeError];
        written = written && [[NSFileManager defaultManager] fileExistsAtPath:path];
        [writeError retain];
        [pool release];
        dispatch_async(dispatch_get_main_queue(), ^{
            OMDShareItem *item = nil;
            NSError *error = nil;
            if (written) {
                item = [[[OMDShareItem alloc] initWithTitle:title
                                                     format:format
                                                    fileURL:[NSURL fileURLWithPath:path]
                                               renderedText:rendered] autorelease];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
                error = writeError != nil ? writeError
                                          : OMDShareError(OMDShareErrorWriteFailed, failure);
            }
            done(item, error);
            [done release];
            [writeError release];
            [markdown release];
            [converter release];
            [directory release];
            [title release];
            [path release];
            [resourceDirectory release];
            [rendered release];
            [failure release];
        });
    });
}

@end
