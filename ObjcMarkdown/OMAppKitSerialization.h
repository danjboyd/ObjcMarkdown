// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>

// GNUstep AppKit keeps process-global, unguarded state: the font cache, the
// shared NSFontManager, and the paragraph-style defaults. Building text objects
// on several threads at once corrupts that state and takes the process down.
// Every place in this library that creates AppKit text objects takes this lock,
// so callers may render and build themes from any thread; what they give up is
// doing two of those at the same time.
FOUNDATION_EXPORT NSRecursiveLock *OMAppKitGlobalLock(void);
