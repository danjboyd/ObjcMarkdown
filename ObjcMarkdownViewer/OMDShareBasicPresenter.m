// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDSharePresenter.h"
#import "OMDShareNotice.h"

// The query value of a mailto: link: everything but letters and digits
// percent-encoded, as RFC 6068 asks.
static NSString *OMDMailtoEncoded(NSString *value)
{
    NSMutableCharacterSet *allowed = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [allowed addCharactersInString:@"-._~"];
    NSString *encoded = [value stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return encoded != nil ? encoded : @"";
}

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
    NSString *link = [NSString stringWithFormat:@"mailto:?subject=%@", OMDMailtoEncoded([item title])];
    NSURL *url = [NSURL URLWithString:link];
    BOOL opened = (url != nil && [[NSWorkspace sharedWorkspace] openURL:url]);
    NSString *message = opened
        ? [NSString stringWithFormat:@"Attach \u201C%@\u201D to the email.", [item fileName]]
        : [NSString stringWithFormat:@"No email app opened. \u201C%@\u201D is ready to attach.", [item fileName]];
    [OMDShareNotice showNoticeWithMessage:message
                                shareItem:item
                                presenter:self
                                forWindow:window];
}

- (void)showShareItemInFolder:(OMDShareItem *)item
{
    NSString *path = [[item fileURL] path];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    if (![workspace selectFile:path inFileViewerRootedAtPath:@""]) {
        [workspace openFile:[path stringByDeletingLastPathComponent]];
    }
}

- (void)copyFileOfShareItem:(OMDShareItem *)item
{
    NSString *path = [[item fileURL] path];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSURLPboardType, NSStringPboardType, nil]
                       owner:nil];
    [pasteboard setPropertyList:[NSArray arrayWithObject:path] forType:NSFilenamesPboardType];
    [[item fileURL] writeToPasteboard:pasteboard];
    [pasteboard setString:path forType:NSStringPboardType];
}

@end
