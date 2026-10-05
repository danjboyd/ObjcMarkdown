// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDViewerColors.h"

NSString * const OMDThemeDefaultsKey = @"GSTheme";

// Whether the desktop theme is dark, judged from its window background (the
// Adwaita theme picks its palette from GNOME's colour scheme at launch).
BOOL OMDSystemAppearanceIsDark(void)
{
    NSColor *background = [[NSColor windowBackgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (background == nil) {
        return NO;
    }
    CGFloat luminance = 0.2126 * [background redComponent] + 0.7152 * [background greenComponent] +
                        0.0722 * [background blueComponent];
    return luminance < 0.5;
}

NSString *OMDColorDefaultsString(NSColor *color)
{
    if (color == nil) {
        return nil;
    }
    @try {
        NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (rgb == nil) {
            return nil;
        }
        return [NSString stringWithFormat:@"%.6f,%.6f,%.6f,%.6f",
                                          [rgb redComponent],
                                          [rgb greenComponent],
                                          [rgb blueComponent],
                                          [rgb alphaComponent]];
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

NSColor *OMDColorFromDefaultsString(NSString *value)
{
    if (value == nil || [value length] == 0) {
        return nil;
    }
    NSArray *parts = [value componentsSeparatedByString:@","];
    if ([parts count] != 4) {
        return nil;
    }

    CGFloat red = [[parts objectAtIndex:0] doubleValue];
    CGFloat green = [[parts objectAtIndex:1] doubleValue];
    CGFloat blue = [[parts objectAtIndex:2] doubleValue];
    CGFloat alpha = [[parts objectAtIndex:3] doubleValue];

    if (red < 0.0 || red > 1.0 || green < 0.0 || green > 1.0 || blue < 0.0 || blue > 1.0 || alpha < 0.0 || alpha > 1.0) {
        return nil;
    }
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static BOOL OMDColorRGBAComponents(NSColor *color,
                                   CGFloat *red,
                                   CGFloat *green,
                                   CGFloat *blue,
                                   CGFloat *alpha)
{
    if (color == nil) {
        return NO;
    }
    @try {
        NSColor *rgbColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        if (rgbColor == nil) {
            return NO;
        }
        if (red != NULL) {
            *red = [rgbColor redComponent];
        }
        if (green != NULL) {
            *green = [rgbColor greenComponent];
        }
        if (blue != NULL) {
            *blue = [rgbColor blueComponent];
        }
        if (alpha != NULL) {
            *alpha = [rgbColor alphaComponent];
        }
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

BOOL OMDColorIsDark(NSColor *color)
{
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    if (!OMDColorRGBAComponents(color, &red, &green, &blue, NULL)) {
        return NO;
    }
    return ((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) < 0.55;
}

NSColor *OMDColorByBlending(NSColor *baseColor, NSColor *mixColor, CGFloat fraction)
{
    CGFloat baseRed = 0.0;
    CGFloat baseGreen = 0.0;
    CGFloat baseBlue = 0.0;
    CGFloat baseAlpha = 1.0;
    CGFloat mixRed = 0.0;
    CGFloat mixGreen = 0.0;
    CGFloat mixBlue = 0.0;
    CGFloat mixAlpha = 1.0;

    if (fraction < 0.0) {
        fraction = 0.0;
    } else if (fraction > 1.0) {
        fraction = 1.0;
    }

    if (!OMDColorRGBAComponents(baseColor, &baseRed, &baseGreen, &baseBlue, &baseAlpha) ||
        !OMDColorRGBAComponents(mixColor, &mixRed, &mixGreen, &mixBlue, &mixAlpha)) {
        return baseColor;
    }

    return [NSColor colorWithCalibratedRed:(baseRed + ((mixRed - baseRed) * fraction))
                                     green:(baseGreen + ((mixGreen - baseGreen) * fraction))
                                      blue:(baseBlue + ((mixBlue - baseBlue) * fraction))
                                     alpha:(baseAlpha + ((mixAlpha - baseAlpha) * fraction))];
}

// The chrome's colours are the theme's system colours; the app picks
// none of its own.
NSColor *OMDResolvedControlTextColor(void)
{
    return [NSColor controlTextColor];
}

NSColor *OMDResolvedMutedTextColor(void)
{
    return [NSColor secondaryLabelColor];
}

NSColor *OMDResolvedChromeBackgroundColor(void)
{
    return [NSColor windowBackgroundColor];
}

NSColor *OMDResolvedPanelBackdropColor(void)
{
    return [NSColor windowBackgroundColor];
}

NSColor *OMDResolvedControlBackgroundColor(void)
{
    return [NSColor controlBackgroundColor];
}

NSColor *OMDResolvedPanelCardFillColor(void)
{
    return [NSColor controlBackgroundColor];
}

NSColor *OMDResolvedSubtleSeparatorColor(void)
{
    return [NSColor controlShadowColor];
}

NSColor *OMDResolvedPanelCardBorderColor(void)
{
    return [NSColor controlShadowColor];
}

NSColor *OMDResolvedAccentColor(void)
{
    return [NSColor selectedControlColor];
}
