// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>

// Stable identifiers for source blocks, used to match a rendered block with
// its source after edits elsewhere move it. Each source line is normalised
// (lowercase letters and digits, other runs as one space) and hashed once;
// any line range's signature then comes from prefix hashes in constant time,
// so nested containers no longer cost their whole span each.
@interface OMBlockSignatureIndex : NSObject

- (instancetype)initWithSourceLines:(NSArray *)sourceLines;

// Signature of 1-based lines startLine...endLine (clamped to the source).
- (NSString *)signatureForStartLine:(NSUInteger)startLine endLine:(NSUInteger)endLine;

// "type|signature": the block ID the renderer and split sync both use.
- (NSString *)blockIDForNodeType:(int)nodeType startLine:(NSUInteger)startLine endLine:(NSUInteger)endLine;

@end
