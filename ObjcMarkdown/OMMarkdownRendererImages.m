// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Images: resolving destinations, loading, caching and remote warming.

#import "OMMarkdownRendererInternal.h"

static NSCache *OMImageAttachmentCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        [cache setCountLimit:256];
    });
    return cache;
}

static dispatch_queue_t OMRemoteImageQueue(void)
{
    static dispatch_queue_t queue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.objcmarkdown.remote-images", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSMutableSet *OMPendingRemoteImageCacheKeys(void)
{
    static NSMutableSet *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [[NSMutableSet alloc] init];
    });
    return keys;
}

static NSString *OMImageAttachmentCacheKey(NSString *urlKey,
                                           CGFloat scale,
                                           CGFloat layoutWidth,
                                           BOOL allowRemoteImages)
{
    return [NSString stringWithFormat:@"%@|%.2f|%.1f|allowRemote:%d",
            urlKey,
            scale,
            layoutWidth,
            (int)(allowRemoteImages ? 1 : 0)];
}

@interface OMImageAttachmentCell (OMFitting)
- (NSURL *)omSourceURL;
@end

@implementation OMImageAttachmentCell

- (instancetype)initImageCell:(NSImage *)image sourceURL:(NSURL *)sourceURL
{
    self = [super initImageCell:image];
    if (self != nil) {
        _sourceURL = [sourceURL copy];
    }
    return self;
}

- (void)dealloc
{
    [_sourceURL release];
    [super dealloc];
}

- (NSURL *)omSourceURL
{
    return _sourceURL;
}

- (NSImage *)fullImage
{
    if ([_sourceURL isFileURL]) {
        NSImage *full = [[[NSImage alloc] initWithContentsOfFile:[_sourceURL path]] autorelease];
        if (full != nil) {
            return full;
        }
    }
    return [self image];
}

@end

// The bitmap behind image, if it is 8 bits per sample, meshed, in grey or
// RGB with or without alpha: the formats pictures load as.
static NSBitmapImageRep *OMEightBitBitmapForImage(NSImage *image)
{
    NSBitmapImageRep *bitmap = nil;
    for (NSImageRep *rep in [image representations]) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmap = (NSBitmapImageRep *)rep;
            break;
        }
    }
    if (bitmap == nil) {
        NSData *tiff = [image TIFFRepresentation];
        bitmap = (tiff != nil ? [NSBitmapImageRep imageRepWithData:tiff] : nil);
    }
    if (bitmap == nil || [bitmap bitsPerSample] != 8 || [bitmap isPlanar] ||
        ([bitmap bitmapFormat] & NSFloatingPointSamplesBitmapFormat) != 0 ||
        [bitmap bitmapData] == NULL) {
        return nil;
    }
    NSInteger samples = [bitmap samplesPerPixel];
    BOOL alpha = [bitmap hasAlpha];
    if (samples != (alpha ? 2 : 1) && samples != (alpha ? 4 : 3)) {
        return nil;
    }
    if ([bitmap bitsPerPixel] != samples * 8) {
        return nil;
    }
    return bitmap;
}

// A copy of image scaled down to size points (one pixel each), averaging
// the source pixels under each new one. Writes the pixels itself rather
// than drawing, since an image drawn into with -lockFocus can come out
// blank on some backends. Returns nil for a bitmap format it doesn't read.
static NSImage *OMDownscaledImage(NSImage *image, NSSize size)
{
    NSBitmapImageRep *source = OMEightBitBitmapForImage(image);
    NSInteger width = (NSInteger)ceil(size.width);
    NSInteger height = (NSInteger)ceil(size.height);
    if (source == nil || width < 1 || height < 1) {
        return nil;
    }
    NSInteger sourceWidth = [source pixelsWide];
    NSInteger sourceHeight = [source pixelsHigh];
    if (sourceWidth < width || sourceHeight < height) {
        return nil;
    }

    NSInteger samples = [source samplesPerPixel];
    BOOL hasAlpha = [source hasAlpha];
    BOOL grey = (samples <= 2);
    NSBitmapFormat format = [source bitmapFormat];
    BOOL alphaFirst = hasAlpha && (format & NSAlphaFirstBitmapFormat) != 0;
    BOOL premultiplied = !hasAlpha || (format & NSAlphaNonpremultipliedBitmapFormat) == 0;
    NSInteger colorOffset = alphaFirst ? 1 : 0;
    NSInteger alphaOffset = alphaFirst ? 0 : samples - 1;
    NSInteger sourceRowBytes = [source bytesPerRow];
    const unsigned char *sourceData = [source bitmapData];

    NSBitmapImageRep *scaled = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:width
                                                                        pixelsHigh:height
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSCalibratedRGBColorSpace
                                                                       bytesPerRow:width * 4
                                                                      bitsPerPixel:32] autorelease];
    unsigned char *scaledData = [scaled bitmapData];
    if (scaled == nil || scaledData == NULL) {
        return nil;
    }

    NSInteger y = 0;
    for (; y < height; y++) {
        NSInteger top = (y * sourceHeight) / height;
        NSInteger bottom = MAX(top + 1, ((y + 1) * sourceHeight) / height);
        NSInteger x = 0;
        for (; x < width; x++) {
            NSInteger left = (x * sourceWidth) / width;
            NSInteger right = MAX(left + 1, ((x + 1) * sourceWidth) / width);
            // Sums of premultiplied colour and of alpha.
            unsigned long red = 0;
            unsigned long green = 0;
            unsigned long blue = 0;
            unsigned long alpha = 0;
            NSInteger row = top;
            for (; row < bottom; row++) {
                const unsigned char *pixel = sourceData + (row * sourceRowBytes) + (left * samples);
                NSInteger column = left;
                for (; column < right; column++, pixel += samples) {
                    unsigned long a = hasAlpha ? pixel[alphaOffset] : 255;
                    unsigned long r = pixel[colorOffset];
                    unsigned long g = grey ? r : pixel[colorOffset + 1];
                    unsigned long b = grey ? r : pixel[colorOffset + 2];
                    if (!premultiplied) {
                        r = (r * a + 127) / 255;
                        g = (g * a + 127) / 255;
                        b = (b * a + 127) / 255;
                    }
                    red += r;
                    green += g;
                    blue += b;
                    alpha += a;
                }
            }
            unsigned long count = (unsigned long)((bottom - top) * (right - left));
            unsigned char *out = scaledData + (y * width * 4) + (x * 4);
            out[0] = (unsigned char)((red + count / 2) / count);
            out[1] = (unsigned char)((green + count / 2) / count);
            out[2] = (unsigned char)((blue + count / 2) / count);
            out[3] = (unsigned char)((alpha + count / 2) / count);
        }
    }

    NSImage *result = [[[NSImage alloc] initWithSize:size] autorelease];
    [result addRepresentation:scaled];
    return result;
}

static NSImage *OMPreparedImageForAttachment(NSImage *image,
                                             CGFloat scale,
                                             CGFloat layoutWidth)
{
    if (image == nil) {
        return nil;
    }

    NSImage *preparedImage = [[image copy] autorelease];
    NSSize imageSize = [preparedImage size];
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return preparedImage;
    }

    CGFloat effectiveScale = scale > 0.01 ? scale : 1.0;
    NSSize preparedSize = NSMakeSize(imageSize.width * effectiveScale,
                                     imageSize.height * effectiveScale);
    CGFloat maxWidth = 0.0;
    if (layoutWidth > 0.0) {
        maxWidth = floor(layoutWidth - (24.0 * effectiveScale));
    }
    if (maxWidth > 0.0 && preparedSize.width > maxWidth) {
        CGFloat ratio = maxWidth / preparedSize.width;
        if (ratio > 0.0) {
            CGFloat height = floor(preparedSize.height * ratio);
            if (height < 1.0) {
                height = 1.0;
            }
            preparedSize = NSMakeSize(maxWidth, height);
        }
    }
    // Drawing a large picture scaled down costs the whole bitmap on every
    // frame, so scrolling past it stutters; scale it once instead.
    NSSize pixelSize = imageSize;
    for (NSImageRep *rep in [image representations]) {
        if ([rep pixelsWide] > 0 && [rep pixelsHigh] > 0) {
            pixelSize = NSMakeSize([rep pixelsWide], [rep pixelsHigh]);
            break;
        }
    }
    if (pixelSize.width > ceil(preparedSize.width) || pixelSize.height > ceil(preparedSize.height)) {
        NSImage *scaled = OMDownscaledImage(image, preparedSize);
        if (scaled != nil) {
            return scaled;
        }
    }
    if (!NSEqualSizes(preparedSize, imageSize)) {
        [preparedImage setScalesWhenResized:YES];
        [preparedImage setSize:preparedSize];
    }
    return preparedImage;
}

static void OMScheduleAsyncRemoteImageWarm(NSURL *url,
                                           NSString *cacheKey,
                                           CGFloat scale,
                                           CGFloat layoutWidth,
                                           BOOL allowRemoteImages)
{
    if (url == nil || cacheKey == nil || [cacheKey length] == 0) {
        return;
    }
    if (!OMURLUsesRemoteScheme(url) || !allowRemoteImages) {
        return;
    }

    NSCache *cache = OMImageAttachmentCache();
    @synchronized (cache) {
        if ([cache objectForKey:cacheKey] != nil) {
            return;
        }
    }

    NSMutableSet *pending = OMPendingRemoteImageCacheKeys();
    BOOL shouldSchedule = NO;
    @synchronized (pending) {
        if (![pending containsObject:cacheKey]) {
            [pending addObject:cacheKey];
            shouldSchedule = YES;
        }
    }
    if (!shouldSchedule) {
        return;
    }

    NSString *urlStringCopy = [[url absoluteString] copy];
    NSString *cacheKeyCopy = [cacheKey copy];
    dispatch_async(OMRemoteImageQueue(), ^{
        @autoreleasepool {
            NSURL *remoteURL = urlStringCopy != nil ? [NSURL URLWithString:urlStringCopy] : nil;
            NSData *data = nil;
            if (remoteURL != nil) {
                data = [NSData dataWithContentsOfURL:remoteURL];
            }
            NSData *dataCopy = [data retain];
            // Not dispatch_get_main_queue(): GNUstep's run loop doesn't drain it on Windows.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (dataCopy != nil && [dataCopy length] > 0) {
                    NSImage *loaded = [[[NSImage alloc] initWithData:dataCopy] autorelease];
                    NSImage *prepared = OMPreparedImageForAttachment(loaded, scale, layoutWidth);
                    if (prepared != nil) {
                        @synchronized (cache) {
                            [cache setObject:prepared forKey:cacheKeyCopy];
                        }
                        [[NSNotificationCenter defaultCenter]
                            postNotificationName:OMMarkdownRendererRemoteImagesDidWarmNotification
                                          object:nil];
                    }
                }
                [dataCopy release];
                @synchronized (pending) {
                    [pending removeObject:cacheKeyCopy];
                }
                [urlStringCopy release];
                [cacheKeyCopy release];
            }];
        }
    });
}

NSString *OMFallbackImageTextForNode(cmark_node *imageNode)
{
    NSString *altText = OMInlinePlainText(imageNode);
    if (altText != nil && [altText length] > 0) {
        return [NSString stringWithFormat:@"[image: %@]", altText];
    }
    return @"[image]";
}

BOOL OMURLUsesRemoteScheme(NSURL *url)
{
    if (url == nil) {
        return NO;
    }
    NSString *scheme = [[url scheme] lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

// A destination as cmark-gfm's HTML renderer writes it into href: UTF-8,
// with everything but letters, digits and -_.+!*'(),%#@?=;:/&$~ as %XX.
// cmark hands over destinations unescaped ("my url", "foo\bar"), which
// NSURL rejects.
static NSString *OMEscapedURLString(NSString *urlString)
{
    static const char *safe = "-_.+!*'(),%#@?=;:/&$~";
    NSData *bytes = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes == nil) {
        return urlString;
    }
    const unsigned char *utf8 = (const unsigned char *)[bytes bytes];
    NSUInteger length = [bytes length];
    NSMutableString *escaped = [NSMutableString stringWithCapacity:length];
    NSUInteger index = 0;
    for (; index < length; index++) {
        unsigned char ch = utf8[index];
        BOOL keep = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
                    (ch != 0 && strchr(safe, ch) != NULL);
        if (keep) {
            [escaped appendFormat:@"%c", ch];
        } else {
            [escaped appendFormat:@"%%%02X", ch];
        }
    }
    return escaped;
}

// Whether the destination starts with a URI scheme ("x:"), which CommonMark
// allows to be 2-32 characters: a letter, then letters, digits, "+", "." or "-".
static BOOL OMDestinationHasScheme(NSString *urlString)
{
    NSUInteger length = [urlString length];
    NSUInteger index = 0;
    for (; index < length && index <= 32; index++) {
        unichar ch = [urlString characterAtIndex:index];
        BOOL letter = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
        BOOL other = (ch >= '0' && ch <= '9') || ch == '+' || ch == '.' || ch == '-';
        if (ch == ':') {
            return index >= 2;
        }
        if (!(letter || (index > 0 && other))) {
            return NO;
        }
    }
    return NO;
}

#if defined(_WIN32)
static BOOL OMIsPathSeparator(unichar ch)
{
    return ch == '/' || ch == '\\';
}

// Whether "server<sep>share..." starts at index: a server name, a
// separator, then a share name.
static BOOL OMHasServerAndShareAtIndex(NSString *string, NSUInteger index)
{
    NSUInteger length = [string length];
    NSUInteger cursor = index;
    while (cursor < length && !OMIsPathSeparator([string characterAtIndex:cursor])) {
        cursor++;
    }
    return cursor > index && cursor + 1 < length &&
           !OMIsPathSeparator([string characterAtIndex:cursor + 1]);
}
#endif

// The destination as a Windows path, or nil if it isn't one. On Windows a
// destination names a file when it has a drive letter ("C:/x.png",
// "C:\x.png"), which NSURL reads as a scheme but CommonMark doesn't (a
// scheme has at least two characters), or when it's a network (UNC) path:
// "\\server\share\x.png" as written, which reaches the renderer as
// "\server\share\x.png" since CommonMark reads "\\" as an escaped
// backslash, or "//server/share/x.png", which NSURL would resolve against
// the document as host "server". UNC paths come back as
// "\\server\share\...". Elsewhere "//host/path" stays a network-path
// reference.
static NSString *OMWindowsPathForDestination(NSString *urlString)
{
#if defined(_WIN32)
    NSUInteger length = [urlString length];
    if (length < 3) {
        return nil;
    }
    unichar first = [urlString characterAtIndex:0];
    unichar second = [urlString characterAtIndex:1];
    if (((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z')) &&
        second == ':' && OMIsPathSeparator([urlString characterAtIndex:2])) {
        return urlString;
    }

    NSUInteger serverStart = 0;
    if (first == second && OMIsPathSeparator(first)) {
        serverStart = 2;
    } else if (first == '\\') {
        serverStart = 1;
    } else {
        return nil;
    }
    if (!OMHasServerAndShareAtIndex(urlString, serverStart)) {
        return nil;
    }
    NSString *rest = [[urlString substringFromIndex:serverStart] stringByReplacingOccurrencesOfString:@"/"
                                                                                           withString:@"\\"];
    return [@"\\\\" stringByAppendingString:rest];
#else
    (void)urlString;
    return nil;
#endif
}

// "http://host?query" or "http://host#fragment" with "/" before the query or
// fragment, which is the same URL (RFC 3986, 6.2.3), or nil if it already
// has a path. GNUstep's NSURL on Windows rejects the form without the "/".
static NSString *OMURLStringWithRootPath(NSString *urlString)
{
    NSString *lower = [urlString lowercaseString];
    NSUInteger start = 0;
    if ([lower hasPrefix:@"http://"]) {
        start = 7;
    } else if ([lower hasPrefix:@"https://"]) {
        start = 8;
    } else {
        return nil;
    }
    NSRange end = [urlString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]
                                             options:0
                                               range:NSMakeRange(start, [urlString length] - start)];
    if (end.location == NSNotFound || [urlString characterAtIndex:end.location] == '/') {
        return nil;
    }
    return [NSString stringWithFormat:@"%@/%@", [urlString substringToIndex:end.location],
                                                [urlString substringFromIndex:end.location]];
}

// The destination as an NSURL, escaping it the way cmark-gfm would if NSURL
// won't take it as written.
static NSURL *OMURLFromDestination(NSString *urlString, NSURL *baseURL)
{
    NSURL *url = baseURL != nil ? [NSURL URLWithString:urlString relativeToURL:baseURL]
                                : [NSURL URLWithString:urlString];
    if (url == nil) {
        NSString *escaped = OMEscapedURLString(urlString);
        url = baseURL != nil ? [NSURL URLWithString:escaped relativeToURL:baseURL]
                             : [NSURL URLWithString:escaped];
        NSString *rooted = url == nil ? OMURLStringWithRootPath(escaped) : nil;
        if (rooted != nil) {
            url = baseURL != nil ? [NSURL URLWithString:rooted relativeToURL:baseURL]
                                 : [NSURL URLWithString:rooted];
        }
    }
    return url;
}

NSURL *OMResolvedImageURL(NSString *urlString,
                          const OMRenderContext *renderContext)
{
    if (urlString == nil || [urlString length] == 0) {
        return nil;
    }

    NSString *windowsPath = OMWindowsPathForDestination(urlString);
    BOOL drivePath = windowsPath != nil;
    if (drivePath) {
        urlString = windowsPath;
    }
    NSURL *url = drivePath ? nil : OMURLFromDestination(urlString, nil);
    if (url != nil && [url scheme] != nil) {
        if (!OMURLUsesAllowedImageScheme(url)) {
            return nil;
        }
        if (OMURLUsesRemoteScheme(url) && !OMShouldAllowRemoteImages(renderContext)) {
            return nil;
        }
        return [url absoluteURL];
    }

    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    NSURL *baseURL = options != nil ? [options baseURL] : nil;
    if (drivePath) {
        // A document from the web doesn't reach into local drives or shares.
        if (baseURL != nil && ![baseURL isFileURL]) {
            return nil;
        }
    } else if (baseURL != nil) {
        NSURL *resolved = OMURLFromDestination(urlString, baseURL);
        if (resolved != nil) {
            return [resolved absoluteURL];
        }
    }

    NSString *path = [urlString stringByRemovingPercentEncoding];
    if (path == nil || [path length] == 0) {
        path = urlString;
    }
    path = [path stringByExpandingTildeInPath];
    if (![path isAbsolutePath]) {
        if ([baseURL isFileURL]) {
            NSString *basePath = [baseURL path];
            if (basePath != nil && [basePath length] > 0) {
                path = [basePath stringByAppendingPathComponent:path];
            }
        } else {
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            path = [cwd stringByAppendingPathComponent:path];
        }
    }
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    if (!OMURLUsesAllowedImageScheme(fileURL)) {
        return nil;
    }
    return fileURL;
}

static NSImage *OMLoadImageFromURL(NSURL *url)
{
    if (url == nil) {
        return nil;
    }

    if ([url isFileURL]) {
        NSString *path = [url path];
        if (path == nil || [path length] == 0) {
            return nil;
        }
        return [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
    }
    return nil;
}

NSURL *OMResolvedLinkURL(NSString *urlString,
                         const OMRenderContext *renderContext)
{
    if (urlString == nil || [urlString length] == 0) {
        return nil;
    }

    // "#slug" points into this document: keep it relative, so the viewer can
    // match it against heading anchors instead of resolving it to a folder.
    if ([urlString hasPrefix:@"#"]) {
        NSURL *fragmentURL = [NSURL URLWithString:urlString];
        if (fragmentURL == nil) {
            NSString *escaped = [[urlString substringFromIndex:1]
                stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
            fragmentURL = [NSURL URLWithString:[@"#" stringByAppendingString:(escaped != nil ? escaped : @"")]];
        }
        return fragmentURL;
    }

    NSString *windowsPath = OMWindowsPathForDestination(urlString);
    BOOL drivePath = windowsPath != nil;
    if (drivePath) {
        urlString = windowsPath;
    }
    NSURL *url = drivePath ? nil : OMURLFromDestination(urlString, nil);
    if (url != nil && [url scheme] != nil) {
        if (!OMURLUsesAllowedLinkScheme(url)) {
            return nil;
        }
        return [url absoluteURL];
    }
    // "irc://x" or "made-up-scheme:y" that NSURL won't parse is still not a
    // file next to the document.
    if (OMDestinationHasScheme(urlString)) {
        return nil;
    }

    OMMarkdownParsingOptions *options = OMRenderContextParsingOptions(renderContext);
    NSURL *baseURL = options != nil ? [options baseURL] : nil;
    if (drivePath) {
        // A document from the web doesn't link into local drives or shares.
        if (baseURL != nil && ![baseURL isFileURL]) {
            return nil;
        }
    } else if (baseURL != nil) {
        NSURL *resolved = OMURLFromDestination(urlString, baseURL);
        if (resolved != nil) {
            return [resolved absoluteURL];
        }
    }

    NSString *path = [urlString stringByRemovingPercentEncoding];
    if (path == nil || [path length] == 0) {
        path = urlString;
    }
    path = [path stringByExpandingTildeInPath];
    if (![path isAbsolutePath]) {
        if ([baseURL isFileURL]) {
            NSString *basePath = [baseURL path];
            if (basePath != nil && [basePath length] > 0) {
                path = [basePath stringByAppendingPathComponent:path];
            }
        } else {
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            path = [cwd stringByAppendingPathComponent:path];
        }
    }
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    if (!OMURLUsesAllowedLinkScheme(fileURL)) {
        return nil;
    }
    return fileURL;
}

NSAttributedString *OMImageAttachmentAttributedString(cmark_node *imageNode,
                                                      NSMutableDictionary *attributes,
                                                      CGFloat scale,
                                                      const OMRenderContext *renderContext)
{
    if (imageNode == NULL) {
        return nil;
    }

    const char *urlLiteral = cmark_node_get_url(imageNode);
    NSString *urlString = urlLiteral != NULL ? [NSString stringWithUTF8String:urlLiteral] : nil;
    return OMImageAttachmentForURLString(urlString, attributes, scale, renderContext);
}

// The image at urlString (resolved against the document) as an attachment,
// or nil if it can't be had yet (a remote image still loading) or at all.
NSAttributedString *OMImageAttachmentForURLString(NSString *urlString,
                                                  NSMutableDictionary *attributes,
                                                  CGFloat scale,
                                                  const OMRenderContext *renderContext)
{
    NSURL *url = OMResolvedImageURL(urlString, renderContext);
    if (url == nil) {
        return nil;
    }

    NSString *urlKey = [url absoluteString];
    if (urlKey == nil || [urlKey length] == 0) {
        urlKey = urlString;
    }
    if (urlKey == nil || [urlKey length] == 0) {
        return nil;
    }

    BOOL allowRemoteImages = OMShouldAllowRemoteImages(renderContext);
    CGFloat layoutWidth = renderContext != NULL ? renderContext->layoutWidth : 0.0;
    NSString *cacheKey = OMImageAttachmentCacheKey(urlKey,
                                                   scale,
                                                   layoutWidth,
                                                   allowRemoteImages);
    // A local file is read again once it changes on disk.
    if ([url isFileURL]) {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL];
        cacheKey = [NSString stringWithFormat:@"%@|%.6f|%llu",
                    cacheKey,
                    [[fileAttributes fileModificationDate] timeIntervalSinceReferenceDate],
                    [fileAttributes fileSize]];
    }
    NSCache *cache = OMImageAttachmentCache();
    NSImage *cachedImage = nil;
    @synchronized (cache) {
        cachedImage = [cache objectForKey:cacheKey];
    }

    NSImage *preparedImage = nil;
    if (cachedImage != nil) {
        preparedImage = [[cachedImage retain] autorelease];
    } else {
        if (OMURLUsesRemoteScheme(url)) {
            OMScheduleAsyncRemoteImageWarm(url, cacheKey, scale, layoutWidth, allowRemoteImages);
            return nil;
        }

        NSImage *loaded = OMLoadImageFromURL(url);
        if (loaded == nil) {
            return nil;
        }

        preparedImage = OMPreparedImageForAttachment(loaded, scale, layoutWidth);
        if (preparedImage == nil) {
            return nil;
        }
        @synchronized (cache) {
            [cache setObject:preparedImage forKey:cacheKey];
        }

    }

    NSTextAttachment *attachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
    NSTextAttachmentCell *cell = [[[OMImageAttachmentCell alloc] initImageCell:preparedImage sourceURL:url] autorelease];
    [attachment setAttachmentCell:cell];

    NSMutableDictionary *attachmentAttributes = [NSMutableDictionary dictionary];
    if (attributes != nil) {
        [attachmentAttributes addEntriesFromDictionary:attributes];
    }
    [attachmentAttributes setObject:attachment forKey:NSAttachmentAttributeName];

    unichar attachmentChar = NSAttachmentCharacter;
    NSString *attachmentString = [NSString stringWithCharacters:&attachmentChar length:1];
    return [[[NSAttributedString alloc] initWithString:attachmentString
                                            attributes:attachmentAttributes] autorelease];
}

// Images in string wider than width, replaced by copies scaled to it (a
// table cell's images, sized for the whole text width, overflowed their
// column: #83).
NSAttributedString *OMAttributedStringFittingImagesToWidth(NSAttributedString *string, CGFloat width)
{
    if (string == nil || width < 1.0) {
        return string;
    }
    NSMutableAttributedString *result = nil;
    NSUInteger length = [string length];
    NSUInteger index = 0;
    while (index < length) {
        NSRange range = NSMakeRange(index, 1);
        NSTextAttachment *attachment = [string attribute:NSAttachmentAttributeName atIndex:index effectiveRange:&range];
        id cell = [attachment attachmentCell];
        if ([cell isKindOfClass:[OMImageAttachmentCell class]]) {
            NSImage *image = [cell image];
            NSSize size = [image size];
            if (image != nil && size.width > width && size.height > 0.0) {
                NSSize fitted = NSMakeSize(floor(width), MAX(1.0, floor(size.height * width / size.width)));
                NSImage *scaled = OMDownscaledImage(image, fitted);
                if (scaled == nil) {
                    scaled = [[image copy] autorelease];
                    [scaled setScalesWhenResized:YES];
                    [scaled setSize:fitted];
                }
                NSTextAttachment *fittedAttachment = [[[NSTextAttachment alloc] initWithFileWrapper:nil] autorelease];
                OMImageAttachmentCell *fittedCell = [[[OMImageAttachmentCell alloc] initImageCell:scaled
                                                                                        sourceURL:[cell omSourceURL]] autorelease];
                [fittedAttachment setAttachmentCell:fittedCell];
                if (result == nil) {
                    result = [[string mutableCopy] autorelease];
                }
                [result addAttribute:NSAttachmentAttributeName value:fittedAttachment range:range];
            }
        }
        index = MAX(NSMaxRange(range), index + 1);
    }
    return result != nil ? result : string;
}
