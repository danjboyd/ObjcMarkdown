// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDDocumentConverter.h"

@interface OMDPandocConverter : OMDDocumentConverter

+ (OMDPandocConverter *)converterIfAvailable;
- (id)initWithPandocPath:(NSString *)pandocPath;

@end
