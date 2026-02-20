// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

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
