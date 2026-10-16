// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareExporter.h"
#import "OMDDocumentConverter.h"

#include <dispatch/dispatch.h>

#include <errno.h>
#include <signal.h>
#include <unistd.h>

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
#if defined(_WIN32)
    (void)directoryName;
    return NO;
#else
    NSRange dash = [directoryName rangeOfString:@"-"];
    if (dash.location == NSNotFound || dash.location == 0) {
        return NO;
    }
    int pid = [[directoryName substringToIndex:dash.location] intValue];
    if (pid <= 0) {
        return NO;
    }
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

+ (NSString *)temporaryRootDirectory
{
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"MarkdownViewer-share"];
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

- (OMDShareItem *)shareItemForFormat:(OMDShareFormat)format error:(NSError **)error
{
    NSString *sourceText = [_source shareSourceText];
    if (sourceText == nil) {
        if (error != NULL) {
            *error = OMDShareError(OMDShareErrorNoDocument, @"Open or import a document first.");
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
        written = [_source shareWritePDFToPath:path];
        break;
    case OMDShareFormatWord:
    case OMDShareFormatHTML:
        written = [converter exportMarkdown:[_source shareMarkdownText]
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

    return [[[OMDShareItem alloc] initWithTitle:title
                                         format:format
                                        fileURL:[NSURL fileURLWithPath:path]
                                   renderedText:[_source shareRenderedText]] autorelease];
}

- (void)shareItemForFormat:(OMDShareFormat)format
                completion:(void (^)(OMDShareItem *item, NSError *error))completion
{
    if (![[self class] formatNeedsConverter:format]) {
        NSError *error = nil;
        OMDShareItem *item = [self shareItemForFormat:format error:&error];
        completion(item, error);
        return;
    }
    // Everything from the document and the window, read here on the main
    // thread; only Pandoc runs on the queue.
    NSString *markdown = [_source shareMarkdownText];
    if (markdown == nil) {
        completion(nil, OMDShareError(OMDShareErrorNoDocument, @"Open or import a document first."));
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
    NSAttributedString *rendered = [_source shareRenderedText];
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
