// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

extern NSString * const OMDSourceHighlighterOptionHighContrast;
extern NSString * const OMDSourceHighlighterOptionAccentColor;

// Source text has no ligatures (#125). On macOS the source font itself
// has its ligature features off (#346): NSLigatureAttributeName on every
// run made CoreText copy the font for each one, a fifth of the source's
// layout. GNUstep keeps the attribute, which also stops "fi" becoming
// U+FB01 there. The same font on GNUstep.
NSFont *OMDSourceFontWithoutLigatures(NSFont *font);
// Whether the source's runs need NSLigatureAttributeName = 0 (GNUstep).
BOOL OMDSourceTextNeedsLigatureAttribute(void);

// What an incremental colouring pass needs to know about the one before it
// (#333): the lines that pass saw and the edits since. Tell it every edit
// to the characters. A pass with other colours or options than the last
// colours the whole text; -reset makes the next pass do so too.
@interface OMDSourceHighlightState : NSObject
{
    NSData *_lines;
    NSArray *_displayMath;
    NSUInteger _length;
    NSRange _editedRange;
    NSInteger _changeInLength;
    BOOL _hasPass;
    NSColor *_baseColor;
    NSColor *_backgroundColor;
    NSDictionary *_options;
}

// range is where the text changed, in the text as it is now, and delta the
// change in its length (an NSTextStorage's -editedRange and
// -changeInLength).
- (void)noteEditedRange:(NSRange)range changeInLength:(NSInteger)delta;
// The next pass colours the whole text.
- (void)reset;

@end

@interface OMDSourceHighlighter : NSObject

+ (void)highlightTextStorage:(NSTextStorage *)textStorage
               baseTextColor:(NSColor *)baseTextColor
             backgroundColor:(NSColor *)backgroundColor;

+ (void)highlightTextStorage:(NSTextStorage *)textStorage
               baseTextColor:(NSColor *)baseTextColor
             backgroundColor:(NSColor *)backgroundColor
                     options:(NSDictionary *)options
                 targetRange:(NSRange)targetRange;

// Colours only the lines the edits since state's last pass touched,
// widened to the blank lines around them, when everything else is as that
// pass left it; otherwise colours the whole text. Returns the range it
// coloured, or {NSNotFound, 0} when nothing changed.
+ (NSRange)highlightTextStorage:(NSTextStorage *)textStorage
                  baseTextColor:(NSColor *)baseTextColor
                backgroundColor:(NSColor *)backgroundColor
                        options:(NSDictionary *)options
                          state:(OMDSourceHighlightState *)state;

+ (void)highlightAttributedString:(NSMutableAttributedString *)attributedString
                    baseTextColor:(NSColor *)baseTextColor
                  backgroundColor:(NSColor *)backgroundColor;

+ (void)highlightAttributedString:(NSMutableAttributedString *)attributedString
                    baseTextColor:(NSColor *)baseTextColor
                  backgroundColor:(NSColor *)backgroundColor
                          options:(NSDictionary *)options
                      targetRange:(NSRange)targetRange;

@end
