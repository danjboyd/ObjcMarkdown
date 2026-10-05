// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMRenderedObject.h"

NSString * const OMRenderedObjectAttributeName = @"OMRenderedObject";

@implementation OMRenderedObject

@synthesize kind = _kind;
@synthesize source = _source;
@synthesize markdown = _markdown;
@synthesize sourceLineRange = _sourceLineRange;
@synthesize sourceRange = _sourceRange;

- (instancetype)initWithKind:(OMRenderedObjectKind)kind
                      source:(NSString *)source
                    markdown:(NSString *)markdown
             sourceLineRange:(NSRange)sourceLineRange
{
    return [self initWithKind:kind
                       source:source
                     markdown:markdown
              sourceLineRange:sourceLineRange
                  sourceRange:NSMakeRange(NSNotFound, 0)];
}

- (instancetype)initWithKind:(OMRenderedObjectKind)kind
                      source:(NSString *)source
                    markdown:(NSString *)markdown
             sourceLineRange:(NSRange)sourceLineRange
                 sourceRange:(NSRange)sourceRange
{
    self = [super init];
    if (self != nil) {
        _kind = kind;
        _source = [(source != nil ? source : @"") copy];
        _markdown = [(markdown != nil ? markdown : _source) copy];
        _sourceLineRange = sourceLineRange;
        _sourceRange = sourceRange;
    }
    return self;
}

- (void)dealloc
{
    [_source release];
    [_markdown release];
    [super dealloc];
}

- (BOOL)isMath
{
    return _kind == OMRenderedObjectKindInlineMath || _kind == OMRenderedObjectKindDisplayMath;
}

- (void)updateSourcePositionsFromObject:(OMRenderedObject *)object
{
    if (object == nil) {
        return;
    }
    _sourceLineRange = [object sourceLineRange];
    _sourceRange = [object sourceRange];
}

- (NSString *)kindDisplayName
{
    switch (_kind) {
        case OMRenderedObjectKindInlineMath:
        case OMRenderedObjectKindDisplayMath:
            return @"Equation";
        case OMRenderedObjectKindDiagram:
            return @"Diagram";
        case OMRenderedObjectKindTable:
            return @"Table";
        case OMRenderedObjectKindImage:
            return @"Image";
    }
    return @"Object";
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ lines %lu+%lu: %@>",
            NSStringFromClass([self class]),
            [self kindDisplayName],
            (unsigned long)_sourceLineRange.location,
            (unsigned long)_sourceLineRange.length,
            _source];
}

@end
