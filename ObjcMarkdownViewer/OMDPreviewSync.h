// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

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
