// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import "OMExport.h"

typedef NS_ENUM(NSInteger, OMRenderedObjectKind) {
    OMRenderedObjectKindInlineMath = 0,
    OMRenderedObjectKindDisplayMath = 1,
    OMRenderedObjectKindDiagram = 2,
    OMRenderedObjectKindTable = 3,
    OMRenderedObjectKindImage = 4
};

// Attribute on the attachment character of each rendered object (math,
// diagrams, tables, images). The value is an OMRenderedObject.
OM_EXPORT NSString * const OMRenderedObjectAttributeName;

// What a rendered attachment was made from, so it can be copied or traced back.
@interface OMRenderedObject : NSObject

- (instancetype)initWithKind:(OMRenderedObjectKind)kind
                      source:(NSString *)source
                    markdown:(NSString *)markdown
             sourceLineRange:(NSRange)sourceLineRange;
- (instancetype)initWithKind:(OMRenderedObjectKind)kind
                      source:(NSString *)source
                    markdown:(NSString *)markdown
             sourceLineRange:(NSRange)sourceLineRange
                 sourceRange:(NSRange)sourceRange;

@property (nonatomic, readonly) OMRenderedObjectKind kind;
// The object's own source: LaTeX, Mermaid text, table Markdown, or image Markdown.
@property (nonatomic, readonly, copy) NSString *source;
// How the object is written in a Markdown document, delimiters included.
@property (nonatomic, readonly, copy) NSString *markdown;
// 1-based source lines of the enclosing block; location is NSNotFound if unknown.
@property (nonatomic, readonly) NSRange sourceLineRange;
// The object's characters in the Markdown source, delimiters included (for
// example "$a^2$"). Falls back to the whole block's lines when the exact text
// can't be found; location is NSNotFound if unknown.
@property (nonatomic, readonly) NSRange sourceRange;
// YES for inline and display math.
- (BOOL)isMath;

// "Equation", "Diagram", "Table" or "Image", for menu titles.
- (NSString *)kindDisplayName;

// Takes the source line range and source range of the same object in a
// later render, after an edit above it moved it. For a viewer that keeps
// the earlier render's text for what didn't change.
- (void)updateSourcePositionsFromObject:(OMRenderedObject *)object;

@end
