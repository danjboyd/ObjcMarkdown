// ObjcMarkdown
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OMMarkdownHTMLPolicy) {
    OMMarkdownHTMLPolicyRenderAsText = 0,
    OMMarkdownHTMLPolicyIgnore = 1
};

typedef NS_ENUM(NSInteger, OMMarkdownMathRenderingPolicy) {
    OMMarkdownMathRenderingPolicyDisabled = 0,
    OMMarkdownMathRenderingPolicyStyledText = 1,
    OMMarkdownMathRenderingPolicyExternalTools = 2
};

@interface OMMarkdownParsingOptions : NSObject <NSCopying>

@property (nonatomic, assign) NSUInteger cmarkOptions;
@property (nonatomic, retain) NSURL *baseURL;
@property (nonatomic, assign) OMMarkdownHTMLPolicy inlineHTMLPolicy;
@property (nonatomic, assign) OMMarkdownHTMLPolicy blockHTMLPolicy;
@property (nonatomic, assign) BOOL renderImages;
@property (nonatomic, assign) BOOL allowRemoteImages;
@property (nonatomic, assign) BOOL codeSyntaxHighlightingEnabled;
@property (nonatomic, assign) OMMarkdownMathRenderingPolicy mathRenderingPolicy;
@property (nonatomic, assign) NSUInteger maximumMathFormulaLength;
@property (nonatomic, assign) NSTimeInterval externalToolTimeout;

+ (instancetype)defaultOptions;

@end
