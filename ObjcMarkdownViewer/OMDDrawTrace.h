// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

// For UAT builds of #164, not for merging. With OMD_TRACE_DRAW set, counts
// redraw requests and redraws per view class and prints them to stderr
// every 2000 events: what asks for the full-height draws per key, and what
// gets drawn because of it. Does nothing without the variable.
void OMDDrawTraceInstallIfRequested(void);
