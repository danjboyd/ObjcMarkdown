// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDAppDelegate.h"

#if defined(_WIN32)
static NSString * const OMDMathRenderingPolicyDefaultsKey = @"ObjcMarkdownMathRenderingPolicy";
static NSInteger const OMDMathRenderingPolicyExternalToolsValue = 2;
#endif
// The defaults this app starts with (theme, menu style, window decoration),
// registered for this process only: see OMDRegisterDefaultPreferences. None
// of these keys mean anything on macOS, so nothing is registered there.
#if defined(GNUSTEP)
static NSString * const OMDMenuInterfaceStyleDefaultsKey = @"NSMenuInterfaceStyle";
static NSString * const OMDWindowDecorationDefaultsKey = @"GSWindowDecoration";
static NSString * const OMDBackChecksOffsetsWithoutNetRequestsDefaultsKey = @"GSBackChecksOffsetsWithoutNetRequests";
static NSString * const OMDBackChecksOffsetsOnScreenDefaultsKey = @"GSBackChecksOffsetsOnScreen";
static NSString * const OMDSuppressAppIconDefaultsKey = @"GSSuppressAppIcon";
static NSString * const OMDThemeDefaultsKey = @"GSTheme";
#endif

static NSString *OMDApplicationName(void)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *appName = [bundle objectForInfoDictionaryKey:@"ApplicationName"];
    if (![appName isKindOfClass:[NSString class]] || [appName length] == 0) {
        NSDictionary *info = [bundle infoDictionary];
        appName = [info objectForKey:@"ApplicationName"];
    }
    if (![appName isKindOfClass:[NSString class]] || [appName length] == 0) {
        return nil;
    }
    return appName;
}

static void OMDStartupTrace(NSString *message)
{
#if defined(_WIN32)
    if (message == nil || [message length] == 0) {
        return;
    }
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ObjcMarkdown-startup.log"];
    NSData *existing = [NSData dataWithContentsOfFile:logPath];
    if (existing == nil) {
        [[NSData data] writeToFile:logPath atomically:YES];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (handle != nil) {
        [handle seekToEndOfFile];
        NSString *line = [NSString stringWithFormat:@"%@\r\n", message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (data != nil) {
            [handle writeData:data];
        }
        [handle closeFile];
    }
#else
    (void)message;
#endif
}

#if defined(GNUSTEP)
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

static BOOL OMDWindowsThemeBundleExistsInDirectory(NSString *themesRoot, NSString *themeName)
{
    if (themesRoot == nil || [themesRoot length] == 0 || themeName == nil || [themeName length] == 0) {
        return NO;
    }

    NSString *bundlePath = [themesRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.theme",
                                                                                                 themeName]];
    NSString *dllPath = [bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.dll",
                                                                                               themeName]];
    return [[NSFileManager defaultManager] fileExistsAtPath:dllPath];
}

static BOOL OMDWindowsBundledExecutableExists(NSString *relativePath)
{
    NSString *bundleRoot = OMDWindowsInstallRoot();
    if (bundleRoot == nil || [bundleRoot length] == 0 ||
        relativePath == nil || [relativePath length] == 0) {
        return NO;
    }

    NSString *candidate = [bundleRoot stringByAppendingPathComponent:relativePath];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:candidate];
}

static NSString *OMDWindowsPreferredThemeName(void)
{
    NSString *bundleRoot = OMDWindowsInstallRoot();
    NSMutableArray *bundledThemeRoots = [NSMutableArray array];
    NSString *userThemesRoot = [[[NSHomeDirectory() stringByAppendingPathComponent:@"GNUstep"]
        stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Themes"];
    NSString *systemThemesRoot = [[[@"C:\\clang64" stringByAppendingPathComponent:@"lib"]
        stringByAppendingPathComponent:@"GNUstep"] stringByAppendingPathComponent:@"Themes"];
    NSArray *preferredThemes = [NSArray arrayWithObjects:@"WinUITheme", @"WinUXTheme", nil];
    NSString *themeName = nil;

    if (bundleRoot != nil && [bundleRoot length] > 0) {
        [bundledThemeRoots addObject:[[[[bundleRoot stringByAppendingPathComponent:@"runtime"]
            stringByAppendingPathComponent:@"lib"] stringByAppendingPathComponent:@"GNUstep"]
            stringByAppendingPathComponent:@"Themes"]];
        [bundledThemeRoots addObject:[[[[bundleRoot stringByAppendingPathComponent:@"clang64"]
            stringByAppendingPathComponent:@"lib"] stringByAppendingPathComponent:@"GNUstep"]
            stringByAppendingPathComponent:@"Themes"]];
        for (themeName in preferredThemes) {
            for (NSString *bundledThemesRoot in bundledThemeRoots) {
                if (OMDWindowsThemeBundleExistsInDirectory(bundledThemesRoot, themeName)) {
                    return themeName;
                }
            }
        }
    }

    for (themeName in preferredThemes) {
        if (OMDWindowsThemeBundleExistsInDirectory(userThemesRoot, themeName) ||
            OMDWindowsThemeBundleExistsInDirectory(systemThemesRoot, themeName)) {
            return themeName;
        }
    }
    return nil;
}
#endif

static NSString *OMDPreferredThemeName(void)
{
#if defined(_WIN32)
    return OMDWindowsPreferredThemeName();
#else
    return @"Adwaita";
#endif
}

#if defined(_WIN32)
static BOOL OMDWindowsBundledExternalMathToolchainAvailable(void)
{
    return (OMDWindowsBundledExecutableExists(@"runtime\\texlive\\TinyTeX\\bin\\windows\\latex.exe") ||
            OMDWindowsBundledExecutableExists(@"clang64\\texlive\\TinyTeX\\bin\\windows\\latex.exe")) &&
           (OMDWindowsBundledExecutableExists(@"runtime\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe") ||
            OMDWindowsBundledExecutableExists(@"clang64\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe"));
}

static void OMDEnsureWindowsDefaultPreferences(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL changed = NO;
    id value = nil;

    value = [defaults objectForKey:OMDMathRenderingPolicyDefaultsKey];
    if ((value == nil || ![value respondsToSelector:@selector(integerValue)]) &&
        OMDWindowsBundledExternalMathToolchainAvailable()) {
        [defaults setInteger:OMDMathRenderingPolicyExternalToolsValue
                      forKey:OMDMathRenderingPolicyDefaultsKey];
        changed = YES;
    }

    if (changed) {
        [defaults synchronize];
    }

    value = [defaults objectForKey:@"NSMenuLocations"];
    if (value != nil) {
        [defaults removeObjectForKey:@"NSMenuLocations"];
        [defaults synchronize];
        OMDStartupTrace(@"main: cleared stale NSMenuLocations");
    }
}
#endif

// Registered, not written (#335). The registration domain lives only in this
// process, so these reach no other GNUstep app, and it comes last in the
// search list, so anything the user set wins: a global default (Preferences
// writes the global GSTheme, as GNUstep's own preferences do), the app's own
// domain or the command line. This has to run before NSApplication exists:
// the theme and the backend read their defaults while it starts.
static void OMDRegisterDefaultPreferences(void)
{
    NSMutableDictionary *registered = [NSMutableDictionary dictionary];
    NSString *preferredTheme = OMDPreferredThemeName();

    if (preferredTheme != nil && [preferredTheme length] > 0) {
        [registered setObject:preferredTheme forKey:OMDThemeDefaultsKey];
    }
    [registered setObject:@"NSWindows95InterfaceStyle" forKey:OMDMenuInterfaceStyleDefaultsKey];
    [registered setObject:@"Default" forKey:OMDWindowDecorationDefaultsKey];
    [registered setObject:[NSNumber numberWithBool:YES]
                   forKey:OMDBackChecksOffsetsWithoutNetRequestsDefaultsKey];
    [registered setObject:[NSNumber numberWithBool:YES]
                   forKey:OMDBackChecksOffsetsOnScreenDefaultsKey];
    [registered setObject:[NSNumber numberWithBool:YES] forKey:OMDSuppressAppIconDefaultsKey];
    [[NSUserDefaults standardUserDefaults] registerDefaults:registered];

#if defined(_WIN32)
    OMDEnsureWindowsDefaultPreferences();
#endif
}
#endif

static void OMDUncaughtExceptionHandler(NSException *exception)
{
    if (exception == nil) {
        OMDStartupTrace(@"uncaught exception: <nil>");
        return;
    }

    OMDStartupTrace([NSString stringWithFormat:@"uncaught exception name: %@",
                                               [exception name]]);
    OMDStartupTrace([NSString stringWithFormat:@"uncaught exception reason: %@",
                                               [exception reason]]);
    NSArray *symbols = [exception callStackSymbols];
    if (symbols != nil && [symbols count] > 0) {
        OMDStartupTrace(@"uncaught exception stack:");
        for (NSString *symbol in symbols) {
            OMDStartupTrace(symbol);
        }
    }
}

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    OMDStartupTrace(@"main: pool created");
    NSSetUncaughtExceptionHandler(&OMDUncaughtExceptionHandler);
    OMDStartupTrace(@"main: exception handler set");
    NSString *applicationName = OMDApplicationName();
    if (applicationName != nil && [applicationName length] > 0) {
        [[NSProcessInfo processInfo] setProcessName:applicationName];
    }
#if defined(GNUSTEP)
    OMDRegisterDefaultPreferences();
    OMDStartupTrace(@"main: default preferences registered");
#endif
    NSApplication *app = nil;
    @try {
        app = [NSApplication sharedApplication];
        OMDStartupTrace(@"main: sharedApplication ok");
    } @catch (id exception) {
        OMDStartupTrace([NSString stringWithFormat:@"main: sharedApplication threw class=%@ description=%@",
                                                   NSStringFromClass([exception class]),
                                                   exception]);
        NSLog(@"MarkdownViewer: sharedApplication failed: %@", exception);
        [pool drain];
        return 1;
    }
    OMDAppDelegate *delegate = [[OMDAppDelegate alloc] init];
    OMDStartupTrace(@"main: delegate created");
    [app setDelegate:delegate];
    OMDStartupTrace(@"main: delegate set");
    @try {
        [app run];
        OMDStartupTrace(@"main: app run returned");
    } @catch (id exception) {
        OMDStartupTrace([NSString stringWithFormat:@"main: app run threw class=%@ description=%@",
                                                   NSStringFromClass([exception class]),
                                                   exception]);
        NSLog(@"MarkdownViewer: app run failed: %@", exception);
        [delegate release];
        [pool drain];
        return 1;
    }
    [delegate release];
    [pool drain];
    return 0;
}
