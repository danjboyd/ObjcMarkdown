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
#include <stdint.h>
#include <inttypes.h>
#include <stdlib.h>

static char OMDFixtureIdentityNonce[65];

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
    BOOL _tracedErrorPresentation;
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
        _tracedErrorPresentation = NO;
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

- (NSError *)application:(NSApplication *)application
        willPresentError:(NSError *)error
{
    (void)application;
    if (!_tracedErrorPresentation) {
        _tracedErrorPresentation = YES;
        OMDTraceStage("launch.error.will-present");
    }
    return error;
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
    NSWindow *shareWindow = nil;
    for (NSWindow *window in [NSApp windows]) {
        NSView *candidate = OMDFixtureFindIcon([window contentView], &count);
        if (candidate != nil) {
            icon = candidate;
            shareWindow = window;
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
    // The exact icon-containing NSWindow supplies the Share XID, never a title search.
    uintptr_t ownerXID = (uintptr_t)[_owner windowRef];
    uintptr_t shareXID = (uintptr_t)[shareWindow windowRef];
    if (shareWindow == nil || shareWindow == _owner || [icon window] != shareWindow ||
        ![shareWindow isKindOfClass:[NSPanel class]] ||
        ![[shareWindow title] isEqualToString:@"Share"] ||
        ![[_owner title] isEqualToString:@"Share notice fixture - private synthetic file"] ||
        ownerXID == 0 || shareXID == 0 || ownerXID == shareXID ||
        ownerXID > UINT32_MAX || shareXID > UINT32_MAX) {
        _failed = YES;
        fprintf(stderr, "FIXTURE_INVALID native window identity missing\n");
        [self finish:nil];
        return;
    }
    fprintf(stdout, "FIXTURE_XIDS pid=%ld nonce=%s owner=0x%" PRIxPTR " share=0x%" PRIxPTR "\n",
            (long)getpid(), OMDFixtureIdentityNonce, ownerXID, shareXID);
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
    BOOL hasThemeArgument = (argc == 3 && strcmp(argv[1], "-GSTheme") == 0 && argv[2][0] != '\0');
    if (argc != 1 && !hasThemeArgument) {
        fprintf(stderr, "usage: OMD_FIXTURE_PATH=/absolute/private/synthetic.md OMDShareNoticeFixture [-GSTheme name]\n");
        [pool drain];
        return 2;
    }
    NSString *path = [[[NSProcessInfo processInfo] environment]
        objectForKey:@"OMD_FIXTURE_PATH"];
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
    const char *identityNonce = getenv("OMD_FIXTURE_IDENTITY_NONCE");
    if (identityNonce == NULL || strlen(identityNonce) != 64 ||
        strspn(identityNonce, "0123456789abcdef") != 64) {
        fprintf(stderr, "FIXTURE_INVALID per-launch identity nonce missing\n");
        [pool drain];
        return 2;
    }
    memcpy(OMDFixtureIdentityNonce, identityNonce, 64);
    OMDFixtureIdentityNonce[64] = '\0';
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
