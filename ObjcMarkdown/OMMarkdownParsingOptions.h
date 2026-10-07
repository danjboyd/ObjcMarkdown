// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>

// RenderSafeSubset (the default) renders the HTML GitHub READMEs use:
// emphasis, code, links, images, line breaks, centred paragraphs, headings,
// lists, details, rules and simple tables; scripts, styles and embedded
// content are dropped, other tags dropped with their text kept.
typedef NS_ENUM(NSInteger, OMMarkdownHTMLPolicy) {
    OMMarkdownHTMLPolicyRenderAsText = 0,
    OMMarkdownHTMLPolicyIgnore = 1,
    OMMarkdownHTMLPolicyRenderSafeSubset = 2
};

typedef NS_ENUM(NSInteger, OMMarkdownMathRenderingPolicy) {
    OMMarkdownMathRenderingPolicyDisabled = 0,
    OMMarkdownMathRenderingPolicyStyledText = 1,
    OMMarkdownMathRenderingPolicyExternalTools = 2
};

// Mermaid erDiagram blocks either draw, or render as their fenced source.
// There is no third state: "off" and "show the source" would behave the same.
typedef NS_ENUM(NSInteger, OMMarkdownDiagramRenderingPolicy) {
    OMMarkdownDiagramRenderingPolicySourceCode = 0,
    OMMarkdownDiagramRenderingPolicyNative = 1
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
@property (nonatomic, assign) OMMarkdownDiagramRenderingPolicy diagramRenderingPolicy;

+ (instancetype)defaultOptions;

@end
