// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Window tabs on GNUstep. GNUstep has no window tabbing yet, but a theme
// may add Apple's NSWindow tabbing API (danjboyd/gnustep-window-tabbing,
// carried by the Adwaita and WinUI themes until libs-gui has it). It is
// declared here and used only after OMDWindowTabbingAvailable(): then each
// document has a window and windows group as tabs; otherwise documents are
// a window's own tabs. (macOS has the API; OMDDocumentWindows uses it.)
#if defined(GNUSTEP)
typedef NSInteger NSWindowTabbingMode;
enum {
    NSWindowTabbingModeAutomatic = 0,
    NSWindowTabbingModePreferred = 1,
    NSWindowTabbingModeDisallowed = 2
};
typedef NSString *NSWindowTabbingIdentifier;

@interface NSWindow (OMDWindowTabbing)
+ (BOOL)allowsAutomaticWindowTabbing;
+ (void)setAllowsAutomaticWindowTabbing:(BOOL)allows;
- (NSWindowTabbingMode)tabbingMode;
- (void)setTabbingMode:(NSWindowTabbingMode)mode;
- (NSWindowTabbingIdentifier)tabbingIdentifier;
- (void)setTabbingIdentifier:(NSWindowTabbingIdentifier)identifier;
- (void)addTabbedWindow:(NSWindow *)window ordered:(NSWindowOrderingMode)ordered;
- (NSArray *)tabbedWindows;
@end

// The identifier all document windows share, so they tab together.
static NSString * const OMDWindowTabbingIdentifier = @"OMDDocumentWindow";

static inline BOOL OMDWindowTabbingAvailable(void)
{
    return [NSWindow instancesRespondToSelector:@selector(addTabbedWindow:ordered:)];
}
#endif
