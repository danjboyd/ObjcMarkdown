// ObjcMarkdown
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// font at another size. macOS can't find its system font (".SFNS-...")
// again by name, and CoreText substitutes Times, so it goes through the
// font's descriptor there.
static inline NSFont *OMFontAtSize(NSFont *font, CGFloat size)
{
    if (font == nil) {
        return nil;
    }
#if defined(GNUSTEP)
    return [NSFont fontWithName:[font fontName] size:size];
#else
    return [NSFont fontWithDescriptor:[font fontDescriptor] size:size];
#endif
}
