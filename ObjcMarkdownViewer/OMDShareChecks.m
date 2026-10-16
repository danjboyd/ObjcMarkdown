// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareChecks.h"
#import "OMGFMParser.h"
#import "OMMarkdownRenderer.h"

#include <string.h>

@interface OMDShareWarning ()
- (instancetype)initWithKind:(OMDShareWarningKind)kind
                  references:(NSArray *)references
               resolvedPaths:(NSArray *)resolvedPaths
              htmlReferences:(NSArray *)htmlReferences;
@end

@implementation OMDShareWarning

- (instancetype)initWithKind:(OMDShareWarningKind)kind
                  references:(NSArray *)references
               resolvedPaths:(NSArray *)resolvedPaths
              htmlReferences:(NSArray *)htmlReferences
{
    self = [super init];
    if (self != nil) {
        _kind = kind;
        _references = [(references != nil ? references : [NSArray array]) copy];
        _resolvedPaths = [(resolvedPaths != nil ? resolvedPaths : [NSArray array]) copy];
        _htmlReferences = [(htmlReferences != nil ? htmlReferences : [NSArray array]) copy];
    }
    return self;
}

- (void)dealloc
{
    [_references release];
    [_resolvedPaths release];
    [_htmlReferences release];
    [super dealloc];
}

- (OMDShareWarningKind)kind
{
    return _kind;
}

- (NSArray *)references
{
    return _references;
}

- (NSArray *)resolvedPaths
{
    return _resolvedPaths;
}

- (NSArray *)htmlReferences
{
    return _htmlReferences;
}

- (NSString *)messageForFormat:(OMDShareFormat)format
{
    unsigned long count = (unsigned long)[_references count];
    switch (_kind) {
    case OMDShareWarningLocalImages:
        if (format == OMDShareFormatWord) {
            count = (unsigned long)[_htmlReferences count];
            return count == 1
                ? @"1 image written as HTML won't be in the Word file."
                : [NSString stringWithFormat:@"%lu images written as HTML won't be in the Word file.", count];
        }
        return count == 1
            ? @"1 image is only on this computer; the reader won't see it."
            : [NSString stringWithFormat:@"%lu images are only on this computer; the reader won't see them.", count];
    case OMDShareWarningMissingImages:
        return count == 1
            ? @"1 image can't be found, even on this computer."
            : [NSString stringWithFormat:@"%lu images can't be found, even on this computer.", count];
    case OMDShareWarningLocalLinks:
        return count == 1
            ? @"1 link points to a file on this computer; it won't open for the reader."
            : [NSString stringWithFormat:@"%lu links point to files on this computer; they won't open for the reader.", count];
    case OMDShareWarningMath:
        return @"Math may show as TeX source in this format.";
    case OMDShareWarningMermaid:
        return @"Diagrams show as Mermaid source in this format.";
    }
    return @"";
}

- (BOOL)appliesToFormat:(OMDShareFormat)format
{
    switch (_kind) {
    case OMDShareWarningLocalImages:
        // A PDF draws them in. Pandoc embeds ![]() images in a .docx but
        // drops <img>, and its HTML only links them.
        if (format == OMDShareFormatWord) {
            return [_htmlReferences count] > 0;
        }
        return format == OMDShareFormatMarkdown || format == OMDShareFormatHTML;
    case OMDShareWarningMissingImages:
    case OMDShareWarningLocalLinks:
        return YES;
    case OMDShareWarningMath:
        // Pandoc makes Word equations; its HTML (no MathML) leaves harder
        // formulas as TeX.
        return format == OMDShareFormatMarkdown || format == OMDShareFormatHTML;
    case OMDShareWarningMermaid:
        // Only the PDF is drawn by the renderer.
        return format != OMDShareFormatPDF;
    }
    return NO;
}

- (BOOL)suggestsPDF
{
    return _kind == OMDShareWarningLocalImages ||
           _kind == OMDShareWarningMath ||
           _kind == OMDShareWarningMermaid;
}

- (BOOL)offersBundle
{
    return _kind == OMDShareWarningLocalImages;
}

@end

// A reference's scheme ("https", "file"), or nil for a path. A single
// letter is a Windows drive ("C:/x.png"), not a scheme.
static NSString *OMDShareReferenceScheme(NSString *reference)
{
    NSUInteger length = [reference length];
    NSUInteger index = 0;
    for (index = 0; index < length; index++) {
        unichar ch = [reference characterAtIndex:index];
        if (ch == ':') {
            break;
        }
        BOOL letter = ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'));
        BOOL other = ((ch >= '0' && ch <= '9') || ch == '+' || ch == '-' || ch == '.');
        if (!(letter || (index > 0 && other))) {
            return nil;
        }
    }
    if (index >= length || index < 2) {
        return nil;
    }
    return [[reference substringToIndex:index] lowercaseString];
}

// Whether a reference points at this computer (a path or a file: URL), as
// opposed to the web, mail or a place in the document.
static BOOL OMDShareReferenceIsLocal(NSString *reference)
{
    NSString *trimmed = [reference stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed length] == 0 || [trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@"//"]) {
        return NO;
    }
    NSString *scheme = OMDShareReferenceScheme(trimmed);
    return scheme == nil || [scheme isEqualToString:@"file"];
}

static BOOL OMDSharePathIsAbsolute(NSString *path)
{
    if ([path hasPrefix:@"/"] || [path hasPrefix:@"\\\\"]) {
        return YES;
    }
    // "C:\x" or "C:/x".
    if ([path length] >= 3) {
        unichar drive = [path characterAtIndex:0];
        unichar slash = [path characterAtIndex:2];
        BOOL letter = ((drive >= 'a' && drive <= 'z') || (drive >= 'A' && drive <= 'Z'));
        return letter && [path characterAtIndex:1] == ':' && (slash == '/' || slash == '\\');
    }
    return NO;
}

NSString *OMDShareResolvedLocalPath(NSString *reference, NSString *baseDirectory)
{
    if (reference == nil || !OMDShareReferenceIsLocal(reference)) {
        return nil;
    }
    NSString *trimmed = [reference stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([OMDShareReferenceScheme(trimmed) isEqualToString:@"file"]) {
        NSString *path = [[NSURL URLWithString:trimmed] path];
        return [path length] > 0 ? path : nil;
    }
    // A path: without its query or fragment, percent-decoded.
    NSRange cut = [trimmed rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    NSString *path = (cut.location != NSNotFound ? [trimmed substringToIndex:cut.location] : trimmed);
    NSString *decoded = [path stringByRemovingPercentEncoding];
    if (decoded != nil) {
        path = decoded;
    }
    if ([path length] == 0) {
        return nil;
    }
    if ([path hasPrefix:@"~"]) {
        return [path stringByExpandingTildeInPath];
    }
    if (OMDSharePathIsAbsolute(path)) {
        return path;
    }
    if ([baseDirectory length] == 0) {
        return nil;
    }
    return [[baseDirectory stringByAppendingPathComponent:path] stringByStandardizingPath];
}

static void OMDShareAddOnce(NSMutableArray *array, NSString *value)
{
    if (value != nil && [value length] > 0 && ![array containsObject:value]) {
        [array addObject:value];
    }
}

// The src of each <img> in a piece of raw HTML.
static void OMDShareCollectHTMLImageSources(NSString *html, NSMutableArray *sources)
{
    static NSRegularExpression *expression = nil;
    if (expression == nil) {
        expression = [[NSRegularExpression alloc]
            initWithPattern:@"<img\\b[^>]*?\\bsrc\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
                    options:NSRegularExpressionCaseInsensitive
                      error:NULL];
    }
    NSArray *matches = [expression matchesInString:html options:0 range:NSMakeRange(0, [html length])];
    for (NSTextCheckingResult *match in matches) {
        NSUInteger group = 1;
        for (group = 1; group <= 3; group++) {
            NSRange range = [match rangeAtIndex:group];
            if (range.location != NSNotFound) {
                OMDShareAddOnce(sources, [html substringWithRange:range]);
                break;
            }
        }
    }
}

static NSString *OMDShareString(const char *value)
{
    return value != NULL ? [NSString stringWithUTF8String:value] : nil;
}

// The source lines of a block (cmark's 1-based start and end lines).
static NSString *OMDShareBlockSource(cmark_node *node, NSArray *lines)
{
    int start = cmark_node_get_start_line(node);
    int end = cmark_node_get_end_line(node);
    if (start < 1 || end < start || (NSUInteger)start > [lines count]) {
        return @"";
    }
    NSUInteger last = MIN((NSUInteger)end, [lines count]);
    NSRange range = NSMakeRange((NSUInteger)start - 1, last - (NSUInteger)start + 1);
    return [[lines subarrayWithRange:range] componentsJoinedByString:@"\n"];
}

typedef struct {
    NSMutableArray *images;
    NSMutableArray *htmlImages;
    NSMutableArray *links;
    BOOL math;
    BOOL mermaid;
} OMDShareFindings;

static void OMDShareCollect(NSString *markdown, OMDShareFindings *findings)
{
    NSData *utf8 = [markdown dataUsingEncoding:NSUTF8StringEncoding];
    cmark_node *document = OMGFMParseDocument((const char *)[utf8 bytes], (size_t)[utf8 length],
                                              CMARK_OPT_DEFAULT);
    if (document == NULL) {
        return;
    }
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [markdown componentsSeparatedByString:@"\n"]) {
        [lines addObject:([line hasSuffix:@"\r"] ? [line substringToIndex:[line length] - 1] : line)];
    }

    cmark_iter *iterator = cmark_iter_new(document);
    cmark_event_type event;
    while ((event = cmark_iter_next(iterator)) != CMARK_EVENT_DONE) {
        if (event != CMARK_EVENT_ENTER) {
            continue;
        }
        cmark_node *node = cmark_iter_get_node(iterator);
        cmark_node_type type = cmark_node_get_type(node);
        if (type == CMARK_NODE_IMAGE) {
            OMDShareAddOnce(findings->images, OMDShareString(cmark_node_get_url(node)));
        } else if (type == CMARK_NODE_LINK) {
            OMDShareAddOnce(findings->links, OMDShareString(cmark_node_get_url(node)));
        } else if (type == CMARK_NODE_HTML_BLOCK || type == CMARK_NODE_HTML_INLINE) {
            NSString *html = OMDShareString(cmark_node_get_literal(node));
            if (html != nil) {
                NSMutableArray *sources = [NSMutableArray array];
                OMDShareCollectHTMLImageSources(html, sources);
                for (NSString *source in sources) {
                    OMDShareAddOnce(findings->images, source);
                    OMDShareAddOnce(findings->htmlImages, source);
                }
            }
        } else if (type == CMARK_NODE_CODE_BLOCK) {
            NSString *info = OMDShareString(cmark_node_get_fence_info(node));
            NSArray *words = [[info stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                componentsSeparatedByString:@" "];
            if ([[words objectAtIndex:0] isEqualToString:@"mermaid"]) {
                findings->mermaid = YES;
            }
        } else if (!findings->math &&
                   (type == CMARK_NODE_PARAGRAPH || type == CMARK_NODE_HEADING || OMGFMNodeIsTable(node))) {
            findings->math = OMMarkdownTextContainsMath(OMDShareBlockSource(node, lines));
        }
    }
    cmark_iter_free(iterator);
    cmark_node_free(document);
}

NSArray *OMDShareLocalImageReferences(NSString *markdown)
{
    if (markdown == nil) {
        return [NSArray array];
    }
    OMDShareFindings findings = { [NSMutableArray array], [NSMutableArray array], [NSMutableArray array], NO, NO };
    OMDShareCollect(markdown, &findings);
    NSMutableArray *local = [NSMutableArray array];
    for (NSString *reference in findings.images) {
        if (OMDShareReferenceIsLocal(reference)) {
            [local addObject:reference];
        }
    }
    return local;
}

NSArray *OMDShareWarnings(NSString *markdown, NSString *baseDirectory)
{
    NSMutableArray *warnings = [NSMutableArray array];
    if (markdown == nil) {
        return warnings;
    }
    OMDShareFindings findings = { [NSMutableArray array], [NSMutableArray array], [NSMutableArray array], NO, NO };
    OMDShareCollect(markdown, &findings);
    NSFileManager *files = [NSFileManager defaultManager];

    NSMutableArray *localImages = [NSMutableArray array];
    NSMutableArray *localImagePaths = [NSMutableArray array];
    NSMutableArray *localHTMLImages = [NSMutableArray array];
    NSMutableArray *missingImages = [NSMutableArray array];
    for (NSString *reference in findings.images) {
        if (!OMDShareReferenceIsLocal(reference)) {
            continue;
        }
        NSString *path = OMDShareResolvedLocalPath(reference, baseDirectory);
        if (path != nil && [files fileExistsAtPath:path]) {
            [localImages addObject:reference];
            OMDShareAddOnce(localImagePaths, path);
            if ([findings.htmlImages containsObject:reference]) {
                [localHTMLImages addObject:reference];
            }
        } else {
            [missingImages addObject:reference];
        }
    }

    NSMutableArray *localLinks = [NSMutableArray array];
    NSMutableArray *localLinkPaths = [NSMutableArray array];
    for (NSString *reference in findings.links) {
        if (!OMDShareReferenceIsLocal(reference)) {
            continue;
        }
        NSString *path = OMDShareResolvedLocalPath(reference, baseDirectory);
        BOOL exists = (path != nil && [files fileExistsAtPath:path]);
        BOOL fileURL = [OMDShareReferenceScheme(reference) isEqualToString:@"file"];
        // A file: URL is a local link even when the file is gone; a
        // relative path that doesn't exist is likely a link that works
        // where the document is published (a repository's docs).
        if (fileURL || exists) {
            [localLinks addObject:reference];
            if (exists) {
                OMDShareAddOnce(localLinkPaths, path);
            }
        }
    }

    if ([localImages count] > 0) {
        [warnings addObject:[[[OMDShareWarning alloc] initWithKind:OMDShareWarningLocalImages
                                                        references:localImages
                                                     resolvedPaths:localImagePaths
                                                    htmlReferences:localHTMLImages] autorelease]];
    }
    if ([missingImages count] > 0) {
        [warnings addObject:[[[OMDShareWarning alloc] initWithKind:OMDShareWarningMissingImages
                                                        references:missingImages
                                                     resolvedPaths:nil
                                                    htmlReferences:nil] autorelease]];
    }
    if ([localLinks count] > 0) {
        [warnings addObject:[[[OMDShareWarning alloc] initWithKind:OMDShareWarningLocalLinks
                                                        references:localLinks
                                                     resolvedPaths:localLinkPaths
                                                    htmlReferences:nil] autorelease]];
    }
    if (findings.math) {
        [warnings addObject:[[[OMDShareWarning alloc] initWithKind:OMDShareWarningMath
                                                        references:nil
                                                     resolvedPaths:nil
                                                    htmlReferences:nil] autorelease]];
    }
    if (findings.mermaid) {
        [warnings addObject:[[[OMDShareWarning alloc] initWithKind:OMDShareWarningMermaid
                                                        references:nil
                                                     resolvedPaths:nil
                                                    htmlReferences:nil] autorelease]];
    }
    return warnings;
}

NSArray *OMDShareWarningsForFormat(NSArray *warnings, OMDShareFormat format)
{
    NSMutableArray *applying = [NSMutableArray array];
    for (OMDShareWarning *warning in warnings) {
        if ([warning appliesToFormat:format]) {
            [applying addObject:warning];
        }
    }
    return applying;
}
