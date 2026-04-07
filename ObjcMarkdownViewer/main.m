// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDAppDelegate.h"

static NSString * const OMDMathRenderingPolicyDefaultsKey = @"ObjcMarkdownMathRenderingPolicy";
static NSInteger const OMDMathRenderingPolicyExternalToolsValue = 2;

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

static NSString *OMDWindowsInstallRoot(void)
{
#if defined(_WIN32)
    NSString *executablePath = [[NSBundle mainBundle] executablePath];
    if (executablePath == nil || [executablePath length] == 0) {
        return nil;
    }

    return [[[executablePath stringByDeletingLastPathComponent]
        stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
#else
    return nil;
#endif
}

static NSString *OMDWindowsBundledDefaultsToolPath(void)
{
#if defined(_WIN32)
    NSString *bundleRoot = OMDWindowsInstallRoot();
    NSString *defaultsPath = [[bundleRoot stringByAppendingPathComponent:@"clang64"]
        stringByAppendingPathComponent:@"bin\\defaults.exe"];

    if ([[NSFileManager defaultManager] isExecutableFileAtPath:defaultsPath]) {
        return defaultsPath;
    }
#endif
    return @"defaults.exe";
}

static BOOL OMDWindowsThemeBundleExistsInDirectory(NSString *themesRoot, NSString *themeName)
{
#if defined(_WIN32)
    if (themesRoot == nil || [themesRoot length] == 0 || themeName == nil || [themeName length] == 0) {
        return NO;
    }

    NSString *bundlePath = [themesRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.theme",
                                                                                                 themeName]];
    NSString *dllPath = [bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.dll",
                                                                                               themeName]];
    return [[NSFileManager defaultManager] fileExistsAtPath:dllPath];
#else
    (void)themesRoot;
    (void)themeName;
    return NO;
#endif
}

static BOOL OMDWindowsBundledExecutableExists(NSString *relativePath)
{
#if defined(_WIN32)
    NSString *bundleRoot = OMDWindowsInstallRoot();
    if (bundleRoot == nil || [bundleRoot length] == 0 ||
        relativePath == nil || [relativePath length] == 0) {
        return NO;
    }

    NSString *candidate = [bundleRoot stringByAppendingPathComponent:relativePath];
    return [[NSFileManager defaultManager] isExecutableFileAtPath:candidate];
#else
    (void)relativePath;
    return NO;
#endif
}

static NSString *OMDWindowsPreferredThemeName(void)
{
#if defined(_WIN32)
    NSString *preferredTheme = @"WinUITheme";
    NSString *bundleRoot = OMDWindowsInstallRoot();
    NSString *bundledThemesRoot = nil;
    NSString *userThemesRoot = [[[NSHomeDirectory() stringByAppendingPathComponent:@"GNUstep"]
        stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Themes"];
    NSString *systemThemesRoot = [[[@"C:\\clang64" stringByAppendingPathComponent:@"lib"]
        stringByAppendingPathComponent:@"GNUstep"] stringByAppendingPathComponent:@"Themes"];

    if (bundleRoot != nil && [bundleRoot length] > 0) {
        bundledThemesRoot = [[[[bundleRoot stringByAppendingPathComponent:@"clang64"]
            stringByAppendingPathComponent:@"lib"] stringByAppendingPathComponent:@"GNUstep"]
            stringByAppendingPathComponent:@"Themes"];
        if (OMDWindowsThemeBundleExistsInDirectory(bundledThemesRoot, preferredTheme)) {
            return preferredTheme;
        }
    }

    if (OMDWindowsThemeBundleExistsInDirectory(userThemesRoot, preferredTheme) ||
        OMDWindowsThemeBundleExistsInDirectory(systemThemesRoot, preferredTheme)) {
        return preferredTheme;
    }
#endif
    return @"WinUXTheme";
}

static BOOL OMDWindowsBundledExternalMathToolchainAvailable(void)
{
#if defined(_WIN32)
    return OMDWindowsBundledExecutableExists(@"clang64\\texlive\\TinyTeX\\bin\\windows\\latex.exe") &&
           OMDWindowsBundledExecutableExists(@"clang64\\texlive\\TinyTeX\\bin\\windows\\dvipng.exe");
#else
    return NO;
#endif
}

static void OMDEnsureWindowsMenuInterfaceStyle(void)
{
#if defined(_WIN32)
    NSTask *task = [[[NSTask alloc] init] autorelease];
    @try {
        [task setLaunchPath:OMDWindowsBundledDefaultsToolPath()];
        [task setArguments:[NSArray arrayWithObjects:@"write",
                                                     @"NSGlobalDomain",
                                                     @"NSMenuInterfaceStyle",
                                                     @"NSWindows95InterfaceStyle",
                                                     nil]];
        [task launch];
        [task waitUntilExit];
        OMDStartupTrace([NSString stringWithFormat:@"menu style fallback exit=%d",
                                                   [task terminationStatus]]);
    } @catch (id exception) {
        OMDStartupTrace([NSString stringWithFormat:@"menu style fallback threw class=%@ description=%@",
                                                   NSStringFromClass([exception class]),
                                                   exception]);
    }
#endif
}

static void OMDEnsureWindowsDefaultPreferences(void)
{
#if defined(_WIN32)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *globalDomain = [defaults persistentDomainForName:NSGlobalDomain];
    NSMutableDictionary *updatedGlobalDomain = nil;
    BOOL changed = NO;
    id value = nil;

    if (globalDomain != nil) {
        updatedGlobalDomain = [[globalDomain mutableCopy] autorelease];
    } else {
        updatedGlobalDomain = [NSMutableDictionary dictionary];
    }

    value = [globalDomain objectForKey:@"GSTheme"];
    if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
        [updatedGlobalDomain setObject:OMDWindowsPreferredThemeName() forKey:@"GSTheme"];
        changed = YES;
    }

    value = [defaults objectForKey:OMDMathRenderingPolicyDefaultsKey];
    if ((value == nil || ![value respondsToSelector:@selector(integerValue)]) &&
        OMDWindowsBundledExternalMathToolchainAvailable()) {
        [defaults setInteger:OMDMathRenderingPolicyExternalToolsValue
                      forKey:OMDMathRenderingPolicyDefaultsKey];
        changed = YES;
    }

    value = [globalDomain objectForKey:@"NSMenuInterfaceStyle"];
    if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
        [updatedGlobalDomain setObject:@"NSWindows95InterfaceStyle"
                                forKey:@"NSMenuInterfaceStyle"];
        changed = YES;
    }

    if (changed) {
        [defaults setPersistentDomain:updatedGlobalDomain forName:NSGlobalDomain];
    }

    value = [defaults objectForKey:@"NSMenuInterfaceStyle"];
    if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
        [defaults setObject:@"NSWindows95InterfaceStyle" forKey:@"NSMenuInterfaceStyle"];
        changed = YES;
    }

    if (changed) {
        [defaults synchronize];
    }

    value = [[defaults persistentDomainForName:NSGlobalDomain] objectForKey:@"NSMenuInterfaceStyle"];
    if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
        OMDEnsureWindowsMenuInterfaceStyle();
        [defaults synchronize];
    }

    value = [defaults objectForKey:@"NSMenuLocations"];
    if (value != nil) {
        [defaults removeObjectForKey:@"NSMenuLocations"];
        [defaults synchronize];
        OMDStartupTrace(@"main: cleared stale NSMenuLocations");
    }
#endif
}

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
    OMDEnsureWindowsDefaultPreferences();
    OMDStartupTrace(@"main: windows defaults ensured");
    NSApplication *app = nil;
    @try {
        app = [NSApplication sharedApplication];
        OMDStartupTrace(@"main: sharedApplication ok");
    } @catch (id exception) {
        OMDStartupTrace([NSString stringWithFormat:@"main: sharedApplication threw class=%@ description=%@",
                                                   NSStringFromClass([exception class]),
                                                   exception]);
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
        [delegate release];
        [pool drain];
        return 1;
    }
    [delegate release];
    [pool drain];
    return 0;
}
