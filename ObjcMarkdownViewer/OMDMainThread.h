// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// Runs the block on the main thread, later, from any thread. Background
// work reports back through this rather than dispatch_get_main_queue(),
// which GNUstep's run loop doesn't drain on Windows, or NSOperationQueue's
// mainQueue, which GNUstep runs on a worker thread.
void OMDPerformOnMainThread(void (^block)(void));
