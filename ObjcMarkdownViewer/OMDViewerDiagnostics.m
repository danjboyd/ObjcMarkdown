// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDViewerDiagnostics.h"

void OMDStartupTrace(NSString *message)
{
    if (message == nil || [message length] == 0) {
        return;
    }
#if defined(_WIN32)
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ObjcMarkdown-startup.log"];
    NSData *existing = [NSData dataWithContentsOfFile:logPath];
    if (existing == nil) {
        [[NSData data] writeToFile:logPath atomically:YES];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (handle == nil) {
        return;
    }
    [handle seekToEndOfFile];
    NSString *line = [NSString stringWithFormat:@"%@\r\n", message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data != nil) {
        [handle writeData:data];
    }
    [handle closeFile];
#else
    (void)message;
#endif
}

BOOL OMDKeyLatencyProfilingEnabled(void)
{
    static NSInteger enabled = -1;
    if (enabled < 0) {
        NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:@"OMD_KEYLATENCY"];
        enabled = ([value length] > 0 && ![value isEqualToString:@"0"]) ? 1 : 0;
    }
    return enabled == 1;
}

NSTimeInterval OMDKeyLatencyNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

double OMDKeyLatencyThresholdMS(void)
{
    static double threshold = -1.0;
    if (threshold < 0.0) {
        NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:@"OMD_KEYLATENCY_THRESHOLD_MS"];
        threshold = [value length] > 0 ? [value doubleValue] : 4.0;
        if (threshold < 0.0) {
            threshold = 0.0;
        }
    }
    return threshold;
}

double OMDKeyLatencyMS(NSTimeInterval start, NSTimeInterval end)
{
    return (end - start) * 1000.0;
}

BOOL OMDPreviewStyleDiagnosticsEnabled(void)
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *flag = [environment objectForKey:@"OMD_LOG_PREVIEW_STYLE_ATTRS"];
    if (flag == nil || [flag length] == 0) {
        flag = [environment objectForKey:@"OBJCMARKDOWN_LOG_PREVIEW_STYLE_ATTRS"];
    }
    if (flag == nil || [flag length] == 0) {
        return [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownLogPreviewStyleAttrs"];
    }

    NSString *lower = [[flag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [lower isEqualToString:@"1"] ||
           [lower isEqualToString:@"true"] ||
           [lower isEqualToString:@"yes"] ||
           [lower isEqualToString:@"on"];
}

id OMDInfoValueForKey(NSString *key)
{
    if (key == nil || [key length] == 0) {
        return nil;
    }

    NSBundle *bundle = [NSBundle mainBundle];
    id value = [bundle objectForInfoDictionaryKey:key];
    if (value != nil) {
        return value;
    }

    NSDictionary *info = [bundle infoDictionary];
    return [info objectForKey:key];
}

NSString *OMDInfoStringForKey(NSString *key)
{
    id value = OMDInfoValueForKey(key);
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

NSTimeInterval OMDNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

static BOOL OMDTruthyFlagValue(NSString *value)
{
    if (value == nil) {
        return NO;
    }
    NSString *lower = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    return [lower isEqualToString:@"1"] ||
           [lower isEqualToString:@"true"] ||
           [lower isEqualToString:@"yes"] ||
           [lower isEqualToString:@"on"];
}

BOOL OMDPerformanceLoggingEnabled(void)
{
    static BOOL resolved = NO;
    static BOOL enabled = NO;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_PERF_LOG"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_PERF_LOG"];
        }
        if (flag != nil && [flag length] > 0) {
            enabled = OMDTruthyFlagValue(flag);
        } else {
            enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownPerfLog"];
        }
        resolved = YES;
    }
    return enabled;
}

BOOL OMDPrintDiagnosticsEnabled(void)
{
    static BOOL resolved = NO;
    static BOOL enabled = NO;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_PRINT_DIAGNOSTICS"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_PRINT_DIAGNOSTICS"];
        }
        if (flag != nil && [flag length] > 0) {
            enabled = OMDTruthyFlagValue(flag);
        } else {
            enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ObjcMarkdownPrintDiagnostics"];
        }
        resolved = YES;
    }
    return enabled;
}

BOOL OMDLaunchPrintAutomationEnabled(void)
{
    static BOOL resolved = NO;
    static BOOL enabled = NO;
    if (!resolved) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        NSString *flag = [environment objectForKey:@"OMD_AUTOMATION_PRINT_ON_LAUNCH"];
        if (flag == nil || [flag length] == 0) {
            flag = [environment objectForKey:@"OBJCMARKDOWN_AUTOMATION_PRINT_ON_LAUNCH"];
        }
        enabled = OMDTruthyFlagValue(flag);
        resolved = YES;
    }
    return enabled;
}

NSString *OMDLaunchPDFExportAutomationPath(void)
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *path = [environment objectForKey:@"OMD_AUTOMATION_EXPORT_PDF_PATH"];
    if (path == nil || [path length] == 0) {
        path = [environment objectForKey:@"OBJCMARKDOWN_AUTOMATION_EXPORT_PDF_PATH"];
    }
    if (path == nil || [path length] == 0) {
        return nil;
    }
    return [[path stringByExpandingTildeInPath] stringByStandardizingPath];
}

void OMDLogPrintDiagnostics(NSString *message)
{
    if (!OMDPrintDiagnosticsEnabled() || message == nil || [message length] == 0) {
        return;
    }
    NSLog(@"OMDPrint: %@", message);
}
