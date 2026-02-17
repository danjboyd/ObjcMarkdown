// ObjcMarkdown
// SPDX-License-Identifier: Apache-2.0

#import "OMMarkdownParsingOptions.h"

#include <cmark.h>

@implementation OMMarkdownParsingOptions

+ (instancetype)defaultOptions
{
    return [[[self alloc] init] autorelease];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _cmarkOptions = (NSUInteger)CMARK_OPT_DEFAULT;
        _baseURL = nil;
        _inlineHTMLPolicy = OMMarkdownHTMLPolicyRenderAsText;
        _blockHTMLPolicy = OMMarkdownHTMLPolicyRenderAsText;
        _renderImages = YES;
        _allowRemoteImages = NO;
        _codeSyntaxHighlightingEnabled = YES;
        _mathRenderingPolicy = OMMarkdownMathRenderingPolicyStyledText;
        _maximumMathFormulaLength = 2048;
        _externalToolTimeout = 4.0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    OMMarkdownParsingOptions *copy = [[[self class] allocWithZone:zone] init];
    if (copy != nil) {
        [copy setCmarkOptions:self.cmarkOptions];
        [copy setBaseURL:self.baseURL];
        [copy setInlineHTMLPolicy:self.inlineHTMLPolicy];
        [copy setBlockHTMLPolicy:self.blockHTMLPolicy];
        [copy setRenderImages:self.renderImages];
        [copy setAllowRemoteImages:self.allowRemoteImages];
        [copy setCodeSyntaxHighlightingEnabled:self.codeSyntaxHighlightingEnabled];
        [copy setMathRenderingPolicy:self.mathRenderingPolicy];
        [copy setMaximumMathFormulaLength:self.maximumMathFormulaLength];
        [copy setExternalToolTimeout:self.externalToolTimeout];
    }
    return copy;
}

- (void)dealloc
{
    [_baseURL release];
    [super dealloc];
}

@end
