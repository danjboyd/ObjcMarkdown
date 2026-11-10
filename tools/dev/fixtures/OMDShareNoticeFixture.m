// Source-only review draft. Do not build or run without separate approval.
// SPDX-License-Identifier: GPL-2.0-or-later
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import "OMDShareNotice.h"
#import "OMDShareItem.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

static void OMDTraceStage(const char *stage)
{
    struct timespec now = {0, 0};
    clock_gettime(CLOCK_MONOTONIC, &now);
    fprintf(stderr, "FIXTURE_STAGE pid=%ld monotonic=%lld.%09ld %s\n",
            (long)getpid(), (long long)now.tv_sec, now.tv_nsec, stage);
    fflush(stderr);
}

static NSView *OMDFixtureFindIcon(NSView *view, NSUInteger *count)
{
    NSView *found = nil;
    if ([NSStringFromClass([view class]) isEqualToString:@"OMDShareFileDragView"]) {
        *count += 1;
        found = view;
    }
    for (NSView *child in [view subviews]) {
        NSView *candidate = OMDFixtureFindIcon(child, count);
        if (candidate != nil) {
            found = candidate;
        }
    }
    return found;
}

@interface OMDShareNoticeFixture : NSObject <NSApplicationDelegate>
{
    NSString *_syntheticPath;
    NSWindow *_owner;
    BOOL _failed;
    BOOL _finished;
}
- (instancetype)initWithSyntheticPath:(NSString *)path;
- (BOOL)failed;
- (void)recordReady:(NSTimer *)timer;
- (void)finish:(NSTimer *)timer;
@end

@implementation OMDShareNoticeFixture
- (instancetype)initWithSyntheticPath:(NSString *)path
{
    self = [super init];
    if (self != nil) {
        _syntheticPath = [path copy];
    }
    return self;
}

- (void)dealloc
{
    [_syntheticPath release];
    [_owner release];
    [super dealloc];
}

- (BOOL)failed
{
    return _failed;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    OMDTraceStage("delegate.enter");
    _owner = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 640, 320)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
    OMDTraceStage("owner.init.return");
    [_owner setReleasedWhenClosed:NO];
    [_owner setTitle:@"Share notice fixture - private synthetic file"];
    OMDTraceStage("owner.order.enter");
    [_owner makeKeyAndOrderFront:nil];
    OMDTraceStage("owner.order.return");

    OMDShareItem *item = [[[OMDShareItem alloc]
        initWithTitle:@"Synthetic fixture"
               format:OMDShareFormatMarkdown
              fileURL:[NSURL fileURLWithPath:_syntheticPath]
         renderedText:nil] autorelease];
    // Public production entry point and real item. No presenter/service action
    // is invoked; the fixture sends no input, drag, mail or clipboard request.
    OMDTraceStage("notice.show.enter");
    [OMDShareNotice showNoticeWithMessage:@"Synthetic file ready for visual inspection."
                               shareItem:item
                               presenter:nil
                               forWindow:_owner];
    OMDTraceStage("notice.show.return");
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:self
                                  selector:@selector(recordReady:)
                                  userInfo:nil repeats:NO];
    [NSTimer scheduledTimerWithTimeInterval:40.0 target:self
                                  selector:@selector(finish:)
                                  userInfo:nil repeats:NO];
    OMDTraceStage("delegate.timers.scheduled");
}

- (void)recordReady:(NSTimer *)timer
{
    (void)timer;
    OMDTraceStage("ready.timer.enter");
    NSUInteger count = 0;
    NSView *icon = nil;
    for (NSWindow *window in [NSApp windows]) {
        NSView *candidate = OMDFixtureFindIcon([window contentView], &count);
        if (candidate != nil) {
            icon = candidate;
        }
    }
    NSImage *image = [icon isKindOfClass:[NSImageView class]]
        ? [(NSImageView *)icon image] : nil;
    if (count != 1 || image == nil ||
        ![[image name] isEqualToString:@"omd-share-file-symbolic"]) {
        _failed = YES;
        fprintf(stderr, "FIXTURE_INVALID target count=%lu or image identity missing\n",
                (unsigned long)count);
        [self finish:nil];
        return;
    }
    fprintf(stdout, "FIXTURE_READY pid=%ld theme=%s class=%s image=%s\n",
            (long)getpid(), [[[GSTheme theme] name] UTF8String],
            [NSStringFromClass([icon class]) UTF8String], [[image name] UTF8String]);
    fflush(stdout);
    // Readiness is identity evidence, never a visual pass. Capture the guest
    // window externally; do not call drawRect or replace the production view.
}

- (void)finish:(NSTimer *)timer
{
    (void)timer;
    if (_finished) {
        return;
    }
    _finished = YES;
    [OMDShareNotice dismissNoticeForWindow:_owner];
    [_owner orderOut:nil];
    [_owner close];
    [NSApp stop:nil];
}
@end

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    BOOL hasThemeArgument = (argc == 4 && strcmp(argv[2], "-GSTheme") == 0 && argv[3][0] != '\0');
    if (argc != 2 && !hasThemeArgument) {
        fprintf(stderr, "usage: OMDShareNoticeFixture /absolute/private/synthetic.md [-GSTheme name]\n");
        [pool drain];
        return 2;
    }
    NSString *path = [NSString stringWithUTF8String:argv[1]];
    NSString *root = [[[NSProcessInfo processInfo] environment]
        objectForKey:@"OMD_FIXTURE_ROOT"];
    NSString *resolvedPath = [path stringByResolvingSymlinksInPath];
    NSString *resolvedRoot = [root stringByResolvingSymlinksInPath];
    BOOL isDirectory = NO;
    if (![root isAbsolutePath] || ![path isEqualToString:resolvedPath] ||
        ![root isEqualToString:resolvedRoot] ||
        ![path hasPrefix:[root stringByAppendingString:@"/"]] ||
        ![[path lastPathComponent] isEqualToString:@"synthetic.md"] ||
        ![path isAbsolutePath] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] ||
        isDirectory) {
        fprintf(stderr, "FIXTURE_INVALID missing private synthetic file\n");
        [pool drain];
        return 2;
    }
    [[NSProcessInfo processInfo] setProcessName:@"OMDShareNoticeFixture"];
    OMDTraceStage("app.shared.enter");
    [NSApplication sharedApplication];
    OMDTraceStage("app.shared.return");
    OMDShareNoticeFixture *fixture = [[OMDShareNoticeFixture alloc] initWithSyntheticPath:path];
    [NSApp setDelegate:fixture];
    OMDTraceStage("app.run.enter");
    [NSApp run];
    OMDTraceStage("app.run.return");
    int result = [fixture failed] ? 1 : 0;
    [NSApp setDelegate:nil];
    [fixture release];
    [pool drain];
    return result;
}
