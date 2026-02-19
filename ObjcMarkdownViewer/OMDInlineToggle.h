// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>

BOOL OMDComputeInlineToggleEdit(NSString *source,
                                NSRange selection,
                                NSString *prefix,
                                NSString *suffix,
                                NSString *placeholder,
                                NSRange *replaceRangeOut,
                                NSString **replacementOut,
                                NSRange *nextSelectionOut);
