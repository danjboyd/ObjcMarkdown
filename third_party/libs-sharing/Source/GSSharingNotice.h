/* GSSharingNotice.h: the small panel a service shows when the destination
   couldn't take the items itself.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
*/

#import "GSSharingPrivate.h"

/* The message, a line of detail, the file (drag it into a mail or a chat)
   with Copy File and Show in Folder when there is one, and Close. A titled
   utility panel the theme draws, centred on the key window. Non-modal;
   Escape or Close dismisses it. One at a time: a new one replaces the
   old. */
@interface GSSharingNotice : NSObject
{
  NSPanel *_panel;
  NSURL *_fileURL;
}
+ (void) showMessage: (NSString *)message
              detail: (NSString *)detail
                file: (NSURL *)fileURL;
+ (void) dismiss;
@end
