// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// Appends a line to the startup log in the temporary directory on Windows;
// does nothing elsewhere.
void OMDStartupTrace(NSString *message);

// Values from the app bundle's Info.plist, and the timing and logging
// switches set by environment variables or Info.plist flags.
BOOL OMDKeyLatencyProfilingEnabled(void);
NSTimeInterval OMDKeyLatencyNow(void);
double OMDKeyLatencyThresholdMS(void);
double OMDKeyLatencyMS(NSTimeInterval start, NSTimeInterval end);
BOOL OMDPreviewStyleDiagnosticsEnabled(void);
id OMDInfoValueForKey(NSString *key);
NSString *OMDInfoStringForKey(NSString *key);
NSTimeInterval OMDNow(void);
BOOL OMDPerformanceLoggingEnabled(void);
BOOL OMDPrintDiagnosticsEnabled(void);
BOOL OMDLaunchPrintAutomationEnabled(void);
NSString *OMDLaunchPDFExportAutomationPath(void);
void OMDLogPrintDiagnostics(NSString *message);
