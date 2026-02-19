// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

BOOL OMDComputeInlineToggleEdit(NSString *source,
                                NSRange selection,
                                NSString *prefix,
                                NSString *suffix,
                                NSString *placeholder,
                                NSRange *replaceRangeOut,
                                NSString **replacementOut,
                                NSRange *nextSelectionOut);
