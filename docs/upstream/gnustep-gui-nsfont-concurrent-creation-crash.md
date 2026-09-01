# GNUstep GUI: Concurrent `NSFont` Creation Corrupts The Heap

## Filed Upstream

Split into two issues on 2026-09-01, both from the `danjboyd` account:

- `libs-gui` (unsynchronized `globalFontMap` cache):
  https://github.com/gnustep/libs-gui/issues/932
- `libs-back` (concurrent font construction crashing in `libfontconfig`):
  https://github.com/gnustep/libs-back/issues/239

This note is the working write-up the two issues were drawn from.

## Summary

Creating `NSFont` instances from more than one thread reliably corrupts the heap
and crashes the process. A 30-line program whose worker threads do nothing but
call `+[NSFont fontWithName:size:]` crashes on every run.

On macOS, `NSFont` instances are immutable and font lookup is safe from any
thread, so code that is correct against Cocoa crashes under GNUstep. This is the
same class of defect as `libs-base` issue 312 (`NSCache is not thread-safe`),
which was resolved by giving the class an internal lock.

## Environment

- GNUstep Base `1.31`, GUI `0.32`, Back `0.32` (X11 backend)
- `libs-gui` at `f03c34410` (2025-11-18), `libs-back` at `45eeba4` (2026-05-10)
- clang / `libobjc2` / `libdispatch` toolchain
- Debian 13, kernel 6.12.101, `fontconfig` 2.15.0-2.3
- x86_64

## Reproducer

```objc
// clang `gnustep-config --objc-flags` fontrace.m -o fontrace \
//       `gnustep-config --gui-libs` -ldispatch
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

int main(void)
{
    [NSAutoreleasePool new];
    [NSApplication sharedApplication];   // bring the backend up

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    int task = 0;
    for (; task < 200; task++) {
        dispatch_group_async(group, queue, ^{
            @autoreleasepool {
                int i = 0;
                for (; i < 60; i++) {
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
```

Result: **10 crashes in 10 runs**, split between `SIGSEGV` and `SIGABRT` with
glibc reporting `malloc_consolidate(): unaligned fastbin chunk detected`.

## Narrowing

Three variants of that program isolate which path is unsafe.

| Variant | Result |
|---|---|
| As above (concurrent create and release) | 10 / 10 crashed |
| Same, with `@synchronized ([NSFont class])` around the font work | 0 / 10 crashed |
| All 24 fonts created **and retained** on the main thread first, so workers only take the cache-hit path | 0 / 10 crashed |

The read path is fine. What is unsafe is creating fonts concurrently, and
releasing them concurrently.

## Crash Sites

The standalone reproducer crashes inside `libfontconfig`, reached from the
backend:

```text
Thread 18 received signal SIGSEGV
#0  libfontconfig.so.1
#1  libfontconfig.so.1
#2  libgnustep-back-032.bundle
#3  libgnustep-back-032.bundle
#4  libgnustep-back-032.bundle
#5  libgnustep-back-032.bundle
```

In a larger application (a Markdown renderer building attributed strings on
several threads) the same workload also crashed at two other sites across runs:

```text
#0  NSMapRemove () from libgnustep-base.so.1.31
```

```text
#0  objc_msgSend_fpret () from libobjc.so.4.6
#1  libgnustep-gui.so.0.32
#2  -[NSFontManager convertFont:toHaveTrait:]
```

Three different crash sites for one workload is the signature of corrupted
shared state rather than a fault at any single call site.

## Unguarded State Found By Inspection

This part is source inspection rather than something the reproducer proves
directly, but it lines up with the `NSMapRemove` backtrace.

`libs-gui/Source/NSFont.m` keeps a process-global font cache:

```objc
/* Cache all created fonts for reuse. */
static NSMapTable* globalFontMap = 0;                     /* line 209 */
```

It is read and mutated from instance initialisation and from `-dealloc`:

- `NSMapGet(globalFontMap, (void *)key)` — line 842, in
  `-initWithName:matrix:fix:screenFont:role:`
- `NSMapInsert(globalFontMap, (void *)key, (void *)self)` — line 881, same method
- `NSMapRemove(globalFontMap, (void *)key)` — line 904, in `-dealloc`

There is no lock anywhere in the file: `grep -c 'NSLock\|@synchronized\|lock]'`
over `NSFont.m` returns 0. So one thread can be removing a dying font's entry
while another inserts or looks one up, which matches the `NSMapRemove` crash.

Two more process-global structures in the same file look similarly exposed:

- `static NSFont *placeHolder` (line 200), the shared instance that
  `+fontWithName:size:` sends `-initWithName:...` to (lines 724, 762)
- `font_roles[role].cachedFont` (lines 351, 415, 430), the cache behind
  `+systemFontOfSize:` and friends, assigned with `ASSIGN` and torn down with
  `DESTROY` from `setNSFont`

## Impact

Any GNUstep application that renders or measures text off the main thread can
crash, and the crash surfaces far from its cause. Concurrent rendering is a
natural design for a document viewer: the work is CPU-bound, per-document, and
touches no UI. The failure mode is heap corruption, so it can also present as an
unrelated crash minutes later, or as silent data corruption.

## Suggested Fix

Give the font cache the same treatment `NSCache` received: an internal lock
around every access to `globalFontMap`, the `font_roles` cache, and the
`placeHolder` initialisation path in `NSFont.m`. A single static
`NSRecursiveLock` (or a `gs_mutex_t`) held across the cache-check, backend
construction, and insert in `-initWithName:matrix:fix:screenFont:role:`, and
across the `NSMapRemove` in `-dealloc`, would close the window that the
reproducer exercises.

The backend's fontconfig usage needs a look as well, since the standalone
reproducer's own crash lands there. Locking in `NSFont.m` alone may serialise
enough to hide it, which would not be the same as fixing it.

## Workaround In Use

`ObjcMarkdown` now serialises every code path that builds AppKit text objects on
a single process-wide recursive lock, and documents that the attributed strings
its renderer returns must not be used concurrently with another render. That
removed the crash for us (6 crashes in 12 test-suite runs before, 0 in 16 after),
at the cost of giving up parallel rendering.

## References

- `libs-base` issue 312, `NSCache is not thread-safe`:
  https://github.com/gnustep/libs-base/issues/312
- `libs-gui/Source/NSFont.m`:
  https://github.com/gnustep/libs-gui/blob/master/Source/NSFont.m
