// MarkdownViewer Quick Look preview
// SPDX-License-Identifier: GPL-2.0-or-later

// Space bar on a Markdown file in the Finder: the document rendered as
// MarkdownViewer's preview shows it, in light or dark as the system is.
// The extension is sandboxed: it reads the file it is given, not the
// images beside it or on the web.

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "OMMarkdownRenderer.h"
#import "OMMarkdownParsingOptions.h"
#import "OMTheme.h"
#import "OMDTextView.h"
#import "OMDTextFileSupport.h"

static const CGFloat OMDPreviewInsetX = 28.0;
static const CGFloat OMDPreviewInsetY = 22.0;

@interface OMDQuickLookPreviewController : NSViewController <QLPreviewingController>
{
    NSScrollView *_scrollView;
    OMDTextView *_textView;
    NSString *_markdown;
    NSURL *_documentURL;
    CGFloat _renderedWidth;
}
@end

@implementation OMDQuickLookPreviewController

- (void)dealloc
{
    [_scrollView release];
    [_textView release];
    [_markdown release];
    [_documentURL release];
    [super dealloc];
}

- (void)loadView
{
    NSRect frame = NSMakeRect(0.0, 0.0, 820.0, 900.0);
    _scrollView = [[NSScrollView alloc] initWithFrame:frame];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setAutohidesScrollers:YES];
    [_scrollView setBorderType:NSNoBorder];
    [_scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    _textView = [[OMDTextView alloc] initWithFrame:frame];
    [_textView setEditable:NO];
    [_textView setSelectable:YES];
    [_textView setRichText:YES];
    [_textView setDrawsBackground:YES];
    [_textView setTextContainerInset:NSMakeSize(OMDPreviewInsetX, OMDPreviewInsetY)];
    [_textView setVerticallyResizable:YES];
    [_textView setHorizontallyResizable:NO];
    [_textView setAutoresizingMask:NSViewWidthSizable];
    [[_textView textContainer] setWidthTracksTextView:YES];
    [_textView setAccessibilityLabel:@"Preview"];
    [_scrollView setDocumentView:_textView];

    [self setView:_scrollView];
    [self setPreferredContentSize:frame.size];
}

- (BOOL)isDarkAppearance
{
    NSAppearanceName match = [[[self view] effectiveAppearance]
        bestMatchFromAppearancesWithNames:[NSArray arrayWithObjects:NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)render
{
    if (_markdown == nil) {
        return;
    }
    OMMarkdownParsingOptions *options = [OMMarkdownParsingOptions defaultOptions];
    [options setBaseURL:[_documentURL URLByDeletingLastPathComponent]];
    // Nothing outside the sandbox: no helper programs, no network.
    [options setMathRenderingPolicy:OMMarkdownMathRenderingPolicyStyledText];
    [options setAllowRemoteImages:NO];

    OMTheme *theme = [OMTheme defaultThemeForDarkAppearance:[self isDarkAppearance]];
    OMMarkdownRenderer *renderer = [[[OMMarkdownRenderer alloc] initWithTheme:theme parsingOptions:options] autorelease];
    CGFloat width = NSWidth([[_scrollView contentView] bounds]) - 2.0 * OMDPreviewInsetX;
    [renderer setLayoutWidth:MAX(width, 200.0)];
    _renderedWidth = NSWidth([[_scrollView contentView] bounds]);

    NSAttributedString *rendered = [renderer attributedStringFromMarkdown:_markdown];
    [[_textView textStorage] setAttributedString:(rendered != nil ? rendered : [[[NSAttributedString alloc] init] autorelease])];

    NSColor *background = [renderer backgroundColor];
    if (background == nil) {
        background = [NSColor textBackgroundColor];
    }
    [_textView setBackgroundColor:background];
    [_scrollView setBackgroundColor:background];
    // Code blocks and quotes as the app's preview draws them.
    [_textView setCodeBlockRanges:[renderer codeBlockRanges]];
    if (theme.codeBackgroundColor != nil) {
        [_textView setCodeBlockBackgroundColor:theme.codeBackgroundColor];
    }
    if (theme.codeBorderColor != nil) {
        [_textView setCodeBlockBorderColor:theme.codeBorderColor];
    }
    [_textView setCodeBlockPadding:NSMakeSize(20.0, 14.0)];
    [_textView setCodeBlockCornerRadius:6.0];
    [_textView setCodeBlockBorderWidth:1.0];
    [_textView setBlockquoteRanges:[renderer blockquoteRanges]];
    if (theme.blockquoteBorderColor != nil) {
        [_textView setBlockquoteLineColor:theme.blockquoteBorderColor];
    }
    [_textView setBlockquoteLineWidth:3.0];
    if (theme.linkColor != nil) {
        [_textView setLinkTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
            theme.linkColor, NSForegroundColorAttributeName,
            [NSNumber numberWithInt:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName, nil]];
    }
    [_textView setNeedsDisplay:YES];
}

- (void)preparePreviewOfFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError *error))handler
{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    NSString *text = data != nil ? OMDDecodeTextFromData(data, NULL) : nil;
    if (text == nil) {
        handler(error != nil ? error : [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil]);
        return;
    }
    [_markdown release];
    _markdown = [text copy];
    [_documentURL release];
    _documentURL = [url copy];
    [self view];
    [self render];
    handler(nil);
}

// The preview panel resized: tables and pictures fit the new width.
- (void)viewDidLayout
{
    [super viewDidLayout];
    CGFloat width = NSWidth([[_scrollView contentView] bounds]);
    if (_markdown != nil && fabs(width - _renderedWidth) > 24.0) {
        [self render];
    }
}

@end
