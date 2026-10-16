// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"

#if !defined(GNUSTEP)
// macOS: the system's share sheet (NSSharingServicePicker) and Mail. Owned by the macOS session (#170).
// Until it is filled in, it does what the basic presenter does.
@interface OMDSharePresenterMac : OMDShareBasicPresenter
@end

@implementation OMDSharePresenterMac
@end

id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void)
{
    return [[OMDSharePresenterMac alloc] init];
}
#endif
