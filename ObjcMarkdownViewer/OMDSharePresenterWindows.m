// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"

#if defined(GNUSTEP) && defined(_WIN32)
// Windows: the Windows share sheet and MAPI. Owned by the Windows session (#170).
// Until it is filled in, it does what the basic presenter does.
@interface OMDSharePresenterWindows : OMDShareBasicPresenter
@end

@implementation OMDSharePresenterWindows
@end

id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void)
{
    return [[OMDSharePresenterWindows alloc] init];
}
#endif
