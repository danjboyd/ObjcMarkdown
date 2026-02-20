// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDCopyFeedbackBadgeView.h"

@interface OMDCopyFeedbackBadgeView ()
{
    NSString *_text;
    NSFont *_font;
}
@end

@implementation OMDCopyFeedbackBadgeView

+ (NSSize)sizeForText:(NSString *)text font:(NSFont *)font
{
    if (font == nil) {
        font = [NSFont boldSystemFontOfSize:11.0];
    }
    if (font == nil) {
        font = [NSFont systemFontOfSize:11.0];
    }
    if (text == nil) {
        text = @"";
    }

    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           font, NSFontAttributeName,
                           nil];
    NSSize textSize = [text sizeWithAttributes:attrs];
    CGFloat width = ceil(textSize.width + 18.0);
    CGFloat height = ceil(textSize.height + 8.0);
    if (width < 58.0) {
        width = 58.0;
    }
    if (height < 22.0) {
        height = 22.0;
    }
    return NSMakeSize(width, height);
}

- (id)initWithFrame:(NSRect)frameRect text:(NSString *)text font:(NSFont *)font
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _text = [text copy];
        if (_text == nil) {
            _text = [@"" copy];
        }
        _font = [font retain];
        if (_font == nil) {
            _font = [[NSFont boldSystemFontOfSize:11.0] retain];
        }
        if (_font == nil) {
            _font = [[NSFont systemFontOfSize:11.0] retain];
        }
    }
    return self;
}

- (void)dealloc
{
    [_text release];
    [_font release];
    [super dealloc];
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect bounds = [self bounds];
    NSRect badgeRect = NSInsetRect(bounds, 0.5, 0.5);
    CGFloat cornerRadius = 6.0;

    NSBezierPath *badge = [NSBezierPath bezierPathWithRoundedRect:badgeRect
                                                           xRadius:cornerRadius
                                                           yRadius:cornerRadius];

    [[NSColor colorWithCalibratedRed:0.14 green:0.16 blue:0.20 alpha:0.96] setFill];
    [badge fill];

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.12] setStroke];
    [badge setLineWidth:1.0];
    [badge stroke];

    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           _font, NSFontAttributeName,
                           [NSColor colorWithCalibratedWhite:1.0 alpha:1.0], NSForegroundColorAttributeName,
                           nil];
    NSSize textSize = [_text sizeWithAttributes:attrs];
    CGFloat x = floor((bounds.size.width - textSize.width) * 0.5);
    CGFloat y = floor((bounds.size.height - textSize.height) * 0.5);
    [_text drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
}

@end
