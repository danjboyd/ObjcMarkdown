// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <AppKit/AppKit.h>
#import "OMDAppDelegate.h"

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];
    OMDAppDelegate *delegate = [[OMDAppDelegate alloc] init];
    [app setDelegate:delegate];
    [app run];
    [delegate release];
    [pool drain];
    return 0;
}
