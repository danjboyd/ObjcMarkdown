// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMBlockSignatureIndex.h"
#include <stdint.h>
#include <stdlib.h>

static const uint64_t OMBlockHashBase = 1099511628211ULL;

// FNV-1a over a line's normalised form, without building the string.
static uint64_t OMNormalizedLineHash(NSString *line, NSCharacterSet *alphanumeric)
{
    uint64_t hash = 14695981039346656037ULL;
    NSString *lower = [line lowercaseString];
    NSUInteger length = [lower length];
    BOOL pendingSpace = NO;
    BOOL wroteAny = NO;
    NSUInteger index = 0;
    for (; index < length; index++) {
        unichar ch = [lower characterAtIndex:index];
        if (![alphanumeric characterIsMember:ch]) {
            pendingSpace = wroteAny;
            continue;
        }
        if (pendingSpace) {
            hash = (hash ^ (uint64_t)' ') * OMBlockHashBase;
            pendingSpace = NO;
        }
        hash = (hash ^ (uint64_t)ch) * OMBlockHashBase;
        wroteAny = YES;
    }
    return hash;
}

@interface OMBlockSignatureIndex ()
{
    uint64_t *_prefix;
    uint64_t *_powers;
    NSUInteger _lineCount;
}
@end

@implementation OMBlockSignatureIndex

- (instancetype)initWithSourceLines:(NSArray *)sourceLines
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _lineCount = [sourceLines count];
    _prefix = (uint64_t *)calloc(_lineCount + 1, sizeof(uint64_t));
    _powers = (uint64_t *)calloc(_lineCount + 1, sizeof(uint64_t));
    if (_prefix == NULL || _powers == NULL) {
        [self release];
        return nil;
    }
    NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];
    _powers[0] = 1;
    NSUInteger line = 1;
    for (; line <= _lineCount; line++) {
        uint64_t lineHash = OMNormalizedLineHash([sourceLines objectAtIndex:line - 1], alphanumeric);
        _prefix[line] = _prefix[line - 1] * OMBlockHashBase + lineHash;
        _powers[line] = _powers[line - 1] * OMBlockHashBase;
    }
    return self;
}

- (void)dealloc
{
    free(_prefix);
    free(_powers);
    [super dealloc];
}

- (NSString *)signatureForStartLine:(NSUInteger)startLine endLine:(NSUInteger)endLine
{
    if (_lineCount == 0 || startLine == 0 || startLine > _lineCount) {
        return @"_";
    }
    if (endLine < startLine) {
        endLine = startLine;
    }
    if (endLine > _lineCount) {
        endLine = _lineCount;
    }
    NSUInteger span = endLine - startLine + 1;
    uint64_t hash = _prefix[endLine] - _prefix[startLine - 1] * _powers[span];
    return [NSString stringWithFormat:@"%016llx-%lu", (unsigned long long)hash, (unsigned long)span];
}

- (NSString *)blockIDForNodeType:(int)nodeType startLine:(NSUInteger)startLine endLine:(NSUInteger)endLine
{
    return [NSString stringWithFormat:@"%d|%@", nodeType, [self signatureForStartLine:startLine endLine:endLine]];
}

@end
