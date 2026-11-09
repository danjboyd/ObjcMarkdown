// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

@class NSTextView;

double OMDNormalizedLocationRatio(NSUInteger location, NSUInteger length);
NSUInteger OMDMapLocationBetweenLengths(NSUInteger location,
                                        NSUInteger sourceLength,
                                        NSUInteger targetLength);
NSUInteger OMDMapLocationBetweenTexts(NSString *sourceText,
                                      NSUInteger sourceLocation,
                                      NSString *targetText);
NSUInteger OMDMapSourceLocationWithBlockAnchors(NSString *sourceText,
                                                NSUInteger sourceLocation,
                                                NSString *targetText,
                                                NSArray *blockAnchors);
NSUInteger OMDMapTargetLocationWithBlockAnchors(NSString *sourceText,
                                                NSString *targetText,
                                                NSUInteger targetLocation,
                                                NSArray *blockAnchors);

// The blocks the mappings go by, parsed from sourceText: what a renderer's
// -sourceBlockDescriptors are when it collects them.
NSArray *OMDPreviewSyncSourceBlockDescriptors(NSString *sourceText);
// Gives the sync the blocks of sourceText from a render's own parse, so
// mapping in that text doesn't parse it again (#346). Nil does nothing.
void OMDPreviewSyncUseSourceBlockDescriptors(NSString *sourceText, NSArray *descriptors);

// The character at verticalAnchor (0 top, 1 bottom) of what textView shows,
// laying out only as far as that point: a full layout of a large source
// after every edit cost seconds in Split (#346). layoutEverything lays out
// the whole text first, as before, for tests to compare.
NSUInteger OMDVisibleCharacterIndexInTextView(NSTextView *textView,
                                              CGFloat verticalAnchor,
                                              BOOL layoutEverything);
