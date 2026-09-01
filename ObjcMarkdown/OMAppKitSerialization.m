// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMAppKitSerialization.h"

#import <dispatch/dispatch.h>

NSRecursiveLock *OMAppKitGlobalLock(void)
{
    static NSRecursiveLock *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSRecursiveLock alloc] init];
    });
    return lock;
}
