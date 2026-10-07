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

