// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"
#import "OMDShareNotice.h"
#import "OMDExternalTools.h"
#import "OMDShareMail.h"

@implementation OMDShareBasicPresenter

- (void)presentShareItem:(OMDShareItem *)item fromView:(NSView *)view
{
    NSString *message = [NSString stringWithFormat:@"\u201C%@\u201D is ready to share.", [item fileName]];
    [OMDShareNotice showNoticeWithMessage:message
                                shareItem:item
                                presenter:self
                                forWindow:[view window]];
}

- (void)emailShareItem:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    [self emailShareItemWithMailtoDraft:item forWindow:window];
}

- (void)emailShareItemWithMailtoDraft:(OMDShareItem *)item forWindow:(NSWindow *)window
{
    BOOL opened = [self openEmailDraftWithSubject:[item title]];
    NSString *message = opened
        ? [NSString stringWithFormat:@"Attach \u201C%@\u201D to the email.", [item fileName]]
        : [NSString stringWithFormat:@"No email app opened. \u201C%@\u201D is ready to attach.", [item fileName]];
    [OMDShareNotice showNoticeWithMessage:message
                                shareItem:item
                                presenter:self
                                forWindow:window];
}

- (BOOL)openEmailDraftWithSubject:(NSString *)subject
{
    NSURL *url = OMDMailtoURLWithSubject(subject);
    return url != nil && OMDOpenURL(url);
}

- (void)showShareItemInFolder:(OMDShareItem *)item
{
    OMDRevealPathInFileManager([[item folderURL] path]);
}

- (void)copyFileOfShareItem:(OMDShareItem *)item
{
    NSString *path = [[item fileURL] path];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSURLPboardType, NSStringPboardType, nil]
                       owner:nil];
    [pasteboard setPropertyList:[NSArray arrayWithObject:path] forType:NSFilenamesPboardType];
#if defined(GNUSTEP)
    // As text/uri-list bytes: GNUstep keeps a string set for this type
    // serialized, and its X11 server hands that over header and all.
    NSString *uriList = [NSString stringWithFormat:@"%@\r\n", [[item fileURL] absoluteString]];
    [pasteboard setData:[uriList dataUsingEncoding:NSUTF8StringEncoding] forType:NSURLPboardType];
#else
    [[item fileURL] writeToPasteboard:pasteboard];
#endif
    [pasteboard setString:path forType:NSStringPboardType];
}

@end
