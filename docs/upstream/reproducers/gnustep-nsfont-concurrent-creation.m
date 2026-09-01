// Minimal reproducer: concurrent NSFont creation/release corrupts globalFontMap.
// Build: clang `gnustep-config --objc-flags` fontrace.m -o fontrace \
//        `gnustep-config --gui-libs` -ldispatch
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

int main(void)
{
    [NSAutoreleasePool new];
    // The backend must be up before any font can be resolved.
    [NSApplication sharedApplication];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    int task = 0;
    for (; task < 200; task++) {
        dispatch_group_async(group, queue, ^{
            @autoreleasepool {
                int i = 0;
                for (; i < 60; i++) {
                    // Varying sizes give distinct cache keys, so each pool drain
                    // removes entries while other threads insert and look up.
                    NSFont *font = [NSFont fontWithName: @"Helvetica"
                                                   size: 8.0 + (CGFloat)(i % 24)];
                    (void)[font pointSize];
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    printf("completed without crashing\n");
    return 0;
}
