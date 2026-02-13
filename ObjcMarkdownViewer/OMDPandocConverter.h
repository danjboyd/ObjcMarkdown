// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDDocumentConverter.h"

@interface OMDPandocConverter : OMDDocumentConverter

+ (OMDPandocConverter *)converterIfAvailable;
- (id)initWithPandocPath:(NSString *)pandocPath;

@end
