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
