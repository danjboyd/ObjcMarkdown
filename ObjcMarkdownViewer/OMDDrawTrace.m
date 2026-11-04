// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDDrawTrace.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(GNUSTEP)

static NSMutableDictionary *OMDDrawTraceCounts = nil;
static unsigned long OMDDrawTraceEvents = 0;

static void OMDDrawTraceDump(void)
{
    NSArray *keys = [OMDDrawTraceCounts keysSortedByValueUsingSelector:@selector(compare:)];
    NSEnumerator *e = [keys reverseObjectEnumerator];
    NSString *key = nil;
    NSUInteger shown = 0;
    fprintf(stderr, "OMDDrawTrace --- after %lu events\n", OMDDrawTraceEvents);
    while ((key = [e nextObject]) != nil && shown++ < 40) {
        fprintf(stderr, "OMDDrawTrace %8lu %s\n",
                (unsigned long)[[OMDDrawTraceCounts objectForKey:key] unsignedLongValue],
                [key UTF8String]);
    }
    fflush(stderr);
}

static void OMDDrawTraceNote(const char *what, NSView *view, NSRect rect)
{
    if (![NSThread isMainThread]) {
        return;
    }
    NSRect bounds = [view bounds];
    BOOL full = bounds.size.height > 0 && rect.size.height >= bounds.size.height * 0.9;
    NSString *key = [NSString stringWithFormat:@"%s %s %s", what, class_getName([view class]),
                                               rect.size.height > 200.0 ? (full ? "FULL>200" : "part>200") : (full ? "full" : "part")];
    NSNumber *count = [OMDDrawTraceCounts objectForKey:key];
    [OMDDrawTraceCounts setObject:[NSNumber numberWithUnsignedLong:[count unsignedLongValue] + 1] forKey:key];
    if (++OMDDrawTraceEvents % 2000 == 0) {
        OMDDrawTraceDump();
    }
}

typedef void (*OMDSetNeedsRectIMP)(id, SEL, NSRect);
typedef void (*OMDDisplayRectIMP)(id, SEL, NSRect, NSGraphicsContext *);
static OMDSetNeedsRectIMP OMDOriginalSetNeedsRect = NULL;
static OMDDisplayRectIMP OMDOriginalDisplayRect = NULL;

static void OMDTracedSetNeedsRect(id self, SEL _cmd, NSRect rect)
{
    OMDDrawTraceNote("invalidate", self, rect);
    OMDOriginalSetNeedsRect(self, _cmd, rect);
}

static void OMDTracedDisplayRect(id self, SEL _cmd, NSRect rect, NSGraphicsContext *context)
{
    OMDDrawTraceNote("display", self, rect);
    OMDOriginalDisplayRect(self, _cmd, rect, context);
}

void OMDDrawTraceInstallIfRequested(void)
{
    if (getenv("OMD_TRACE_DRAW") == NULL) {
        return;
    }
    OMDDrawTraceCounts = [[NSMutableDictionary alloc] init];
    Method invalidate = class_getInstanceMethod([NSView class], @selector(setNeedsDisplayInRect:));
    OMDOriginalSetNeedsRect = (OMDSetNeedsRectIMP)method_setImplementation(invalidate, (IMP)OMDTracedSetNeedsRect);
    Method display = class_getInstanceMethod([NSView class], @selector(displayRectIgnoringOpacity:inContext:));
    if (display != NULL) {
        OMDOriginalDisplayRect = (OMDDisplayRectIMP)method_setImplementation(display, (IMP)OMDTracedDisplayRect);
    }
    fprintf(stderr, "OMDDrawTrace installed (display hook %s)\n", display != NULL ? "yes" : "no");
}

#else

void OMDDrawTraceInstallIfRequested(void)
{
}

#endif
