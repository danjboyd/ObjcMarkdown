// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDViewerImages.h"
#import "OMDViewerColors.h"

static const CGFloat OMDToolbarIconSize = 22.0;
static const CGFloat OMDToolbarIconInset = 2.0;

NSImage *OMDImageNamed(NSString *resourceName)
{
    if (resourceName == nil || [resourceName length] == 0) {
        return nil;
    }

    NSImage *image = [NSImage imageNamed:resourceName];
    if (image != nil) {
        return image;
    }

    NSString *baseName = [resourceName stringByDeletingPathExtension];
    NSString *extension = [resourceName pathExtension];
    if (extension == nil || [extension length] == 0) {
        extension = @"png";
    }
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:baseName ofType:extension];
    if (resourcePath == nil && [baseName length] > 0) {
        resourcePath = [[NSBundle mainBundle] pathForResource:resourceName ofType:nil];
    }
    if (resourcePath != nil) {
        NSImage *fileImage = [[[NSImage alloc] initWithContentsOfFile:resourcePath] autorelease];
        if (fileImage != nil) {
            return fileImage;
        }
    }
    return nil;
}

static NSImage *OMDToolbarPreparedImage(NSImage *image)
{
    if (image == nil) {
        return nil;
    }

    NSSize targetSize = NSMakeSize(OMDToolbarIconSize, OMDToolbarIconSize);
    NSSize imageSize = [image size];
    NSRect sourceRect = NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height);
    NSData *tiffData = [image TIFFRepresentation];
    if (tiffData != nil) {
        NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithData:tiffData] autorelease];
        NSInteger width = [bitmap pixelsWide];
        NSInteger height = [bitmap pixelsHigh];
        if (width > 0 && height > 0) {
            NSInteger minX = width;
            NSInteger minY = height;
            NSInteger maxX = -1;
            NSInteger maxY = -1;
            NSInteger x = 0;
            NSInteger y = 0;
            for (y = 0; y < height; y++) {
                for (x = 0; x < width; x++) {
                    NSColor *pixel = [bitmap colorAtX:x y:y];
                    if (pixel != nil && [pixel alphaComponent] > 0.01) {
                        if (x < minX) {
                            minX = x;
                        }
                        if (y < minY) {
                            minY = y;
                        }
                        if (x > maxX) {
                            maxX = x;
                        }
                        if (y > maxY) {
                            maxY = y;
                        }
                    }
                }
            }
            if (maxX >= minX && maxY >= minY && imageSize.width > 0.0 && imageSize.height > 0.0) {
                CGFloat scaleX = imageSize.width / (CGFloat)width;
                CGFloat scaleY = imageSize.height / (CGFloat)height;
                sourceRect = NSMakeRect(minX * scaleX,
                                        minY * scaleY,
                                        (maxX - minX + 1) * scaleX,
                                        (maxY - minY + 1) * scaleY);
            }
        }
    }

    NSImage *prepared = [[[NSImage alloc] initWithSize:targetSize] autorelease];
    if (prepared == nil) {
        return image;
    }

    NSRect rect = NSMakeRect(0.0, 0.0, targetSize.width, targetSize.height);
    NSRect drawRect = NSInsetRect(rect, OMDToolbarIconInset, OMDToolbarIconInset);
    if (drawRect.size.width <= 0.0 || drawRect.size.height <= 0.0) {
        drawRect = rect;
    }
    [prepared lockFocus];
    [image drawInRect:drawRect fromRect:sourceRect operation:NSCompositeCopy fraction:1.0];
    [prepared unlockFocus];
    [prepared setSize:targetSize];
    return prepared;
}

void OMDSetToolbarItemImage(NSToolbarItem *item, NSImage *image)
{
    if (item == nil || image == nil) {
        return;
    }

    NSImage *prepared = OMDToolbarPreparedImage(image);
    [item setImage:(prepared != nil ? prepared : image)];
}

NSImage *OMDToolbarImageNamed(NSString *resourceName)
{
    return OMDToolbarPreparedImage(OMDImageNamed(resourceName));
}

NSImage *OMDToolbarTintedImage(NSImage *image, NSColor *tint)
{
    if (image == nil) {
        return nil;
    }

    if (tint == nil) {
        NSImage *prepared = OMDToolbarPreparedImage(image);
        return (prepared != nil ? prepared : image);
    }

    NSImage *prepared = OMDToolbarPreparedImage(image);
    if (prepared != nil) {
        image = prepared;
    }

    NSSize size = [image size];
    if (size.width <= 0.0 || size.height <= 0.0) {
        return image;
    }

    NSData *tiffData = [image TIFFRepresentation];
    NSBitmapImageRep *bitmap = (tiffData != nil
                                ? [[[NSBitmapImageRep alloc] initWithData:tiffData] autorelease]
                                : nil);
    if (bitmap == nil) {
        return image;
    }

    NSColor *rgbTint = [tint colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat tintAlpha = 1.0;
    NSInteger width = [bitmap pixelsWide];
    NSInteger height = [bitmap pixelsHigh];
    NSInteger x = 0;
    NSInteger y = 0;

    if (rgbTint == nil) {
        rgbTint = tint;
    }
    [rgbTint getRed:&red green:&green blue:&blue alpha:&tintAlpha];

    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            NSColor *source = [bitmap colorAtX:x y:y];
            CGFloat sourceAlpha = (source != nil ? [source alphaComponent] : 0.0);
            if (sourceAlpha <= 0.01) {
                [bitmap setColor:[NSColor clearColor] atX:x y:y];
            } else {
                [bitmap setColor:[NSColor colorWithCalibratedRed:red
                                                           green:green
                                                            blue:blue
                                                           alpha:sourceAlpha * tintAlpha]
                              atX:x
                              y:y];
            }
        }
    }

    NSImage *tinted = [[[NSImage alloc] initWithSize:size] autorelease];
    if (tinted == nil) {
        return image;
    }
    [tinted addRepresentation:bitmap];
    [tinted setSize:size];
    return tinted;
}

NSImage *OMDToolbarThemedImageNamed(NSString *resourceName)
{
    return OMDToolbarTintedImage(OMDImageNamed(resourceName), OMDResolvedControlTextColor());
}

NSImage *OMDCodeBlockCopyImage(void)
{
    static NSImage *cached = nil;
    if (cached != nil) {
        return cached;
    }

    NSImage *image = OMDImageNamed(@"code-copy-icon.png");
    if (image == nil) {
        return nil;
    }

    [image setSize:NSMakeSize(16.0, 16.0)];
    cached = [image retain];
    return cached;
}

NSImage *OMDCodeBlockCopiedCheckImage(void)
{
    static NSImage *cached = nil;
    if (cached != nil) {
        return cached;
    }

    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)] autorelease];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:0.13 green:0.62 blue:0.30 alpha:1.0] setStroke];
    NSBezierPath *check = [NSBezierPath bezierPath];
    [check setLineWidth:2.0];
    [check setLineCapStyle:NSRoundLineCapStyle];
    [check setLineJoinStyle:NSRoundLineJoinStyle];
    [check moveToPoint:NSMakePoint(3.2, 8.2)];
    [check lineToPoint:NSMakePoint(6.5, 4.8)];
    [check lineToPoint:NSMakePoint(12.8, 11.2)];
    [check stroke];
    [image unlockFocus];
    [image setSize:NSMakeSize(16.0, 16.0)];
    cached = [image retain];
    return cached;
}
