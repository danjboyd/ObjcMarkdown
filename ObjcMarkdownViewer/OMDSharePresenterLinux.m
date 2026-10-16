// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"

#if defined(GNUSTEP) && !defined(_WIN32)
// Linux and the BSDs: our picker, the email portal or xdg-email, FileManager1. Owned by the Linux session (#170).
// Until it is filled in, it does what the basic presenter does.
@interface OMDSharePresenterLinux : OMDShareBasicPresenter
@end

@implementation OMDSharePresenterLinux
@end

id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void)
{
    return [[OMDSharePresenterLinux alloc] init];
}
#endif
