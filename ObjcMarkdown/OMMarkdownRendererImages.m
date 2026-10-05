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
        NSImage *scaled = [[[NSImage alloc] initWithSize:preparedSize] autorelease];
        [scaled lockFocus];
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationDefault];
        [image drawInRect:NSMakeRect(0.0, 0.0, preparedSize.width, preparedSize.height)
                 fromRect:NSZeroRect
                operation:NSCompositeSourceOver
                 fraction:1.0];
        [scaled unlockFocus];
        return scaled;
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
            dispatch_async(dispatch_get_main_queue(), ^{
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
            });
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
    }
    return url;
}

NSURL *OMResolvedImageURL(NSString *urlString,
                          const OMRenderContext *renderContext)
{
    if (urlString == nil || [urlString length] == 0) {
        return nil;
    }

    NSURL *url = OMURLFromDestination(urlString, nil);
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
    if (baseURL != nil) {
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

    NSURL *url = OMURLFromDestination(urlString, nil);
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
    if (baseURL != nil) {
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
