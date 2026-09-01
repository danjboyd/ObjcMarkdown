// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "OMMermaidERLayout.h"

@class OMMermaidERDiagram;

// Fonts and colors an entity-relationship diagram draws with. Callers build one
// from their theme; the drawing code reads nothing else.
@interface OMMermaidERDrawingStyle : NSObject
{
    NSFont *_titleFont;
    NSFont *_attributeFont;
    NSFont *_labelFont;
    NSColor *_borderColor;
    NSColor *_titleBackgroundColor;
    NSColor *_bodyBackgroundColor;
    NSColor *_textColor;
    NSColor *_keyColor;
    NSColor *_commentColor;
    NSColor *_edgeColor;
    CGFloat _borderWidth;
}

@property (nonatomic, retain) NSFont *titleFont;
@property (nonatomic, retain) NSFont *attributeFont;
@property (nonatomic, retain) NSFont *labelFont;
@property (nonatomic, retain) NSColor *borderColor;
@property (nonatomic, retain) NSColor *titleBackgroundColor;
@property (nonatomic, retain) NSColor *bodyBackgroundColor;
@property (nonatomic, retain) NSColor *textColor;
// Used for the PK/FK/UK markers.
@property (nonatomic, retain) NSColor *keyColor;
@property (nonatomic, retain) NSColor *commentColor;
@property (nonatomic, retain) NSColor *edgeColor;
@property (nonatomic, assign) CGFloat borderWidth;

@end

// Measures with a style's fonts, so layout geometry and drawing agree.
@interface OMMermaidERStyleMeasurer : NSObject <OMMermaidERTextMeasuring>
{
    OMMermaidERDrawingStyle *_style;
}
- (instancetype)initWithStyle:(OMMermaidERDrawingStyle *)style;
@end

// Layout metrics derived from a style's font sizes.
FOUNDATION_EXPORT OMMermaidERLayoutMetrics *OMMermaidERMetricsForStyle(OMMermaidERDrawingStyle *style);

@interface OMMermaidERDiagramAttachmentCell : NSTextAttachmentCell
{
    OMMermaidERDiagramLayout *_layout;
    OMMermaidERDrawingStyle *_style;
    NSFont *_scaledTitleFont;
    NSFont *_scaledAttributeFont;
    NSFont *_scaledLabelFont;
    CGFloat _drawScale;
}

- (instancetype)initWithLayout:(OMMermaidERDiagramLayout *)layout
                         style:(OMMermaidERDrawingStyle *)style
                     drawScale:(CGFloat)drawScale;

@property (nonatomic, readonly) OMMermaidERDiagramLayout *layout;
// 1.0 unless the diagram had to shrink to fit the available width.
@property (nonatomic, readonly) CGFloat drawScale;

@end

// Lays the diagram out and returns a one-character attributed string carrying the
// drawing attachment, or nil when the diagram cannot be laid out. maximumWidth of
// zero or less means no width constraint.
FOUNDATION_EXPORT NSAttributedString *OMMermaidERAttachmentAttributedString(OMMermaidERDiagram *diagram,
                                                                           OMMermaidERDrawingStyle *style,
                                                                           CGFloat maximumWidth,
                                                                           NSDictionary *attributes);
