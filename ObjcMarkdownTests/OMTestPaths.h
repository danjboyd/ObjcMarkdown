// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// An absolute path for a test that spells it in POSIX form ("/a/b"). On
// Windows "/a/b" has no drive, so GNUstep doesn't treat it as absolute (and
// won't resolve ".." in it); the same path on drive C: is.
static inline NSString *OMTestAbsolutePath(NSString *posixPath)
{
#if defined(_WIN32)
    return [@"C:" stringByAppendingString:posixPath];
#else
    return posixPath;
#endif
}
