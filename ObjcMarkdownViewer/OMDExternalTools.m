// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDExternalTools.h"
#import <AppKit/AppKit.h>
#import "OMDTextFileSupport.h"

#if defined(_WIN32)
static NSString *OMDWindowsInstallRoot(void)
{
    NSString *executablePath = [[NSBundle mainBundle] executablePath];
    if (executablePath == nil || [executablePath length] == 0) {
        return nil;
    }

    return [[[executablePath stringByDeletingLastPathComponent]
        stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
}

static BOOL OMDWindowsBundledExecutableExists(NSString *relativePath)
{
    NSString *installRoot = OMDWindowsInstallRoot();
    if (installRoot == nil || [installRoot length] == 0 ||
        relativePath == nil || [relativePath length] == 0) {
        return NO;
    }

    NSString *candidate = [installRoot stringByAppendingPathComponent:relativePath];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:candidate];
}

BOOL OMDWindowsBundledExternalMathToolchainAvailable(void)
{
    return (OMDWindowsBundledExecutableExists(@"runtime\\texlive\\TinyTeX\\bin\\windows\\latex.exe") ||
            OMDWindowsBundledExecutableExists(@"clang64\\texlive\\TinyTeX\\bin\\windows\\latex.exe")) &&
           (OMDWindowsBundledExecutableExists(@"runtime\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe") ||
            OMDWindowsBundledExecutableExists(@"clang64\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe"));
}
#endif

static NSArray *OMDExecutableCandidateNames(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return [NSArray array];
    }
#if defined(_WIN32)
    return [NSArray arrayWithObjects:name,
                                      [name stringByAppendingString:@".exe"],
                                      [name stringByAppendingString:@".cmd"],
                                      [name stringByAppendingString:@".bat"],
                                      nil];
#else
    return [NSArray arrayWithObject:name];
#endif
}

static NSArray *OMDExecutableSearchDirectories(void)
{
    NSMutableArray *directories = [NSMutableArray array];
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *pathValue = [environment objectForKey:@"PATH"];
    if (pathValue != nil && [pathValue length] > 0) {
#if defined(_WIN32)
        NSArray *searchPaths = [pathValue componentsSeparatedByString:@";"];
#else
        NSArray *searchPaths = [pathValue componentsSeparatedByString:@":"];
#endif
        for (NSString *searchPath in searchPaths) {
            if (searchPath != nil && [searchPath length] > 0) {
                [directories addObject:searchPath];
            }
        }
    }

#if defined(_WIN32)
    [directories addObjectsFromArray:@[
        @"C:/msys64/usr/bin",
        @"C:/msys64/clang64/bin",
        @"C:/clang64/bin"
    ]];
#else
    [directories addObject:@"/usr/bin"];
#endif

    return directories;
}

NSString *OMDExecutablePathNamed(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *candidateNames = OMDExecutableCandidateNames(name);
    NSArray *searchPaths = OMDExecutableSearchDirectories();
    for (NSString *searchPath in searchPaths) {
        if (searchPath == nil || [searchPath length] == 0) {
            continue;
        }
        for (NSString *candidateName in candidateNames) {
            NSString *candidate = [searchPath stringByAppendingPathComponent:candidateName];
            if ([fileManager isExecutableFileAtPath:candidate]) {
                return candidate;
            }
        }
    }

    return nil;
}

BOOL OMDLooksLikeWindowsAbsolutePath(NSString *path)
{
#if defined(_WIN32)
    if (path == nil || [path length] < 2) {
        return NO;
    }

    unichar first = [path characterAtIndex:0];
    unichar second = [path characterAtIndex:1];
    if (((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z')) &&
        second == ':') {
        return YES;
    }

    if ([path hasPrefix:@"\\\\"] || [path hasPrefix:@"//"]) {
        return YES;
    }
#else
    (void)path;
#endif
    return NO;
}

NSString *OMDNormalizedExternalLocalPath(NSString *path)
{
    NSString *trimmed = OMDTrimmedString(path);
    if ([trimmed length] == 0) {
        return nil;
    }

    if ([trimmed hasPrefix:@"file://"]) {
        NSURL *url = [NSURL URLWithString:trimmed];
        if (url != nil && [url isFileURL]) {
            NSString *urlPath = [url path];
            if ([urlPath length] > 0) {
                trimmed = urlPath;
            }
        }
    }

#if defined(_WIN32)
    if ([trimmed rangeOfString:@"\\"].location != NSNotFound) {
        trimmed = [trimmed stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    }
#endif

    return trimmed;
}

#if defined(_WIN32)
NSString *OMDHTMLEscapedString(NSString *value)
{
    if (value == nil) {
        return @"";
    }

    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return escaped;
}
#endif

BOOL OMDOpenURLUsingXDGOpen(NSURL *url)
{
#if defined(__APPLE__)
    (void)url;
    return NO;
#else
    if (url == nil) {
        return NO;
    }

    NSString *xdgOpenPath = @"/usr/bin/xdg-open";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:xdgOpenPath]) {
        return NO;
    }

    NSString *urlString = [url absoluteString];
    if (urlString == nil || [urlString length] == 0) {
        return NO;
    }

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:xdgOpenPath];
    [task setArguments:[NSArray arrayWithObject:urlString]];

    BOOL launched = YES;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        launched = NO;
    }

    return launched && [task terminationStatus] == 0;
#endif
}

static BOOL OMDRunTask(NSString *launchPath, NSArray *arguments)
{
    if (launchPath == nil) {
        return NO;
    }
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:launchPath];
    [task setArguments:arguments];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return NO;
    }
    return [task terminationStatus] == 0;
}

BOOL OMDOpenFolderInFileManager(NSString *folder)
{
    if ([folder length] == 0) {
        return NO;
    }
#if defined(_WIN32)
    return OMDRunTask(OMDExecutablePathNamed(@"explorer"), [NSArray arrayWithObject:folder]);
#else
    NSURL *url = [NSURL fileURLWithPath:folder isDirectory:YES];
    if ([[NSWorkspace sharedWorkspace] respondsToSelector:@selector(openURL:)] &&
        [[NSWorkspace sharedWorkspace] openURL:url]) {
        return YES;
    }
    return OMDOpenURLUsingXDGOpen(url);
#endif
}

BOOL OMDRevealPathInFileManager(NSString *path)
{
    if ([path length] == 0) {
        return NO;
    }
#if defined(_WIN32)
    // Explorer exits with 1 even when it worked.
    OMDRunTask(OMDExecutablePathNamed(@"explorer"),
               [NSArray arrayWithObject:[NSString stringWithFormat:@"/select,%@", path]]);
    return YES;
#else
    // The freedesktop file-manager interface selects the item (Files,
    // Dolphin, Nemo, Caja...); without one, open the folder.
    NSString *gdbus = OMDExecutablePathNamed(@"gdbus");
    if (gdbus != nil) {
        NSString *uri = [[NSURL fileURLWithPath:path] absoluteString];
        NSArray *arguments = [NSArray arrayWithObjects:@"call", @"--session",
                              @"--dest", @"org.freedesktop.FileManager1",
                              @"--object-path", @"/org/freedesktop/FileManager1",
                              @"--method", @"org.freedesktop.FileManager1.ShowItems",
                              [NSString stringWithFormat:@"['%@']", [uri stringByReplacingOccurrencesOfString:@"'" withString:@"%27"]],
                              @"", nil];
        if (OMDRunTask(gdbus, arguments)) {
            return YES;
        }
    }
    return OMDOpenFolderInFileManager([path stringByDeletingLastPathComponent]);
#endif
}

static NSSet *OMDAllowedLinkSchemes(void)
{
    static NSSet *schemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        schemes = [[NSSet alloc] initWithObjects:@"file", @"http", @"https", @"mailto", nil];
    });
    return schemes;
}

BOOL OMDShouldOpenURLForUserNavigation(NSURL *url)
{
    if (url == nil) {
        return NO;
    }
    NSString *scheme = [[url scheme] lowercaseString];
    if (scheme == nil || [scheme length] == 0) {
        return NO;
    }
    return [OMDAllowedLinkSchemes() containsObject:scheme];
}
