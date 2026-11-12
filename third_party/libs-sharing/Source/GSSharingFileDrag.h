/* Shared file-icon drag threshold. No drag session starts on a plain click.
   Copyright (C) 2026 Daniel Boyd
   SPDX-License-Identifier: LGPL-2.1-or-later */
#ifndef GS_SHARING_FILE_DRAG_H
#define GS_SHARING_FILE_DRAG_H

#import <AppKit/AppKit.h>

static inline BOOL
GSSharingFileDragShouldBegin(NSPoint start, NSPoint current, NSEventType type)
{
  const CGFloat threshold = 4.0;
  CGFloat dx = current.x - start.x;
  CGFloat dy = current.y - start.y;

  return type == NSLeftMouseDragged
    && dx * dx + dy * dy >= threshold * threshold;
}

/* Consume the release if the press never becomes a drag. Pass the actual
   dragged event to dragFile:, which starts tracking at its current position. */
static inline NSEvent *
GSSharingFileDragStartEvent(NSEvent *mouseDown)
{
  NSPoint start;
  NSEvent *event;

  if ([mouseDown type] != NSLeftMouseDown)
    return nil;

  start = [mouseDown locationInWindow];
  for (;;)
    {
      event = [NSApp nextEventMatchingMask:
        NSLeftMouseDraggedMask | NSLeftMouseUpMask
        untilDate: [NSDate distantFuture]
        inMode: NSEventTrackingRunLoopMode
        dequeue: YES];
      if (event == nil || [event type] == NSLeftMouseUp)
        return nil;
      if (GSSharingFileDragShouldBegin(start, [event locationInWindow],
                                      [event type]))
        return event;
    }
}

#endif
