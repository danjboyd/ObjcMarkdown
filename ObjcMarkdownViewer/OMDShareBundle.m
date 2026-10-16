// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareBundle.h"
#import "OMDShareChecks.h"

#include <time.h>

uint32_t OMDShareCRC32(NSData *data)
{
    static uint32_t table[256];
    static BOOL built = NO;
    if (!built) {
        uint32_t index = 0;
        for (index = 0; index < 256; index++) {
            uint32_t value = index;
            int bit = 0;
            for (bit = 0; bit < 8; bit++) {
                value = (value & 1) ? (0xEDB88320u ^ (value >> 1)) : (value >> 1);
            }
            table[index] = value;
        }
        built = YES;
    }
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    NSUInteger length = [data length];
    uint32_t crc = 0xFFFFFFFFu;
    NSUInteger index = 0;
    for (index = 0; index < length; index++) {
        crc = table[(crc ^ bytes[index]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

static void OMDZipAppend16(NSMutableData *data, uint16_t value)
{
    uint8_t bytes[2] = { (uint8_t)(value & 0xFF), (uint8_t)(value >> 8) };
    [data appendBytes:bytes length:2];
}

static void OMDZipAppend32(NSMutableData *data, uint32_t value)
{
    uint8_t bytes[4] = {
        (uint8_t)(value & 0xFF), (uint8_t)((value >> 8) & 0xFF),
        (uint8_t)((value >> 16) & 0xFF), (uint8_t)(value >> 24)
    };
    [data appendBytes:bytes length:4];
}

BOOL OMDShareWriteZip(NSString *path, NSArray *names, NSArray *contents)
{
    if (path == nil || [names count] != [contents count] || [names count] > 0xFFFF) {
        return NO;
    }
    // The entries' time, in MS-DOS form.
    time_t now = time(NULL);
    struct tm local;
#if defined(_WIN32)
    localtime_s(&local, &now);
#else
    localtime_r(&now, &local);
#endif
    uint16_t dosTime = (uint16_t)((local.tm_hour << 11) | (local.tm_min << 5) | (local.tm_sec / 2));
    uint16_t dosDate = (uint16_t)(((local.tm_year - 80) << 9) | ((local.tm_mon + 1) << 5) | local.tm_mday);
    // Bit 11: the names are UTF-8.
    const uint16_t flags = 0x0800;

    NSMutableData *archive = [NSMutableData data];
    NSMutableData *directory = [NSMutableData data];
    NSUInteger index = 0;
    for (index = 0; index < [names count]; index++) {
        NSData *name = [[names objectAtIndex:index] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *content = [contents objectAtIndex:index];
        if ([name length] > 0xFFFF || [content length] > 0xFFFFFFFEu || [archive length] > 0xFFFFFFFEu) {
            return NO;
        }
        uint32_t crc = OMDShareCRC32(content);
        uint32_t size = (uint32_t)[content length];
        uint32_t offset = (uint32_t)[archive length];

        OMDZipAppend32(archive, 0x04034b50u);
        OMDZipAppend16(archive, 20);
        OMDZipAppend16(archive, flags);
        OMDZipAppend16(archive, 0);
        OMDZipAppend16(archive, dosTime);
        OMDZipAppend16(archive, dosDate);
        OMDZipAppend32(archive, crc);
        OMDZipAppend32(archive, size);
        OMDZipAppend32(archive, size);
        OMDZipAppend16(archive, (uint16_t)[name length]);
        OMDZipAppend16(archive, 0);
        [archive appendData:name];
        [archive appendData:content];

        OMDZipAppend32(directory, 0x02014b50u);
        OMDZipAppend16(directory, 20);
        OMDZipAppend16(directory, 20);
        OMDZipAppend16(directory, flags);
        OMDZipAppend16(directory, 0);
        OMDZipAppend16(directory, dosTime);
        OMDZipAppend16(directory, dosDate);
        OMDZipAppend32(directory, crc);
        OMDZipAppend32(directory, size);
        OMDZipAppend32(directory, size);
        OMDZipAppend16(directory, (uint16_t)[name length]);
        OMDZipAppend16(directory, 0);
        OMDZipAppend16(directory, 0);
        OMDZipAppend16(directory, 0);
        OMDZipAppend16(directory, 0);
        OMDZipAppend32(directory, 0);
        OMDZipAppend32(directory, offset);
        [directory appendData:name];
    }
    if ([archive length] + [directory length] > 0xFFFFFFFEu) {
        return NO;
    }
    uint32_t directoryOffset = (uint32_t)[archive length];
    [archive appendData:directory];
    OMDZipAppend32(archive, 0x06054b50u);
    OMDZipAppend16(archive, 0);
    OMDZipAppend16(archive, 0);
    OMDZipAppend16(archive, (uint16_t)[names count]);
    OMDZipAppend16(archive, (uint16_t)[names count]);
    OMDZipAppend32(archive, (uint32_t)[directory length]);
    OMDZipAppend32(archive, directoryOffset);
    OMDZipAppend16(archive, 0);
    return [archive writeToFile:path atomically:YES];
}

// The name in the bundle of a plain relative reference inside the
// document's folder ("images/a.png" or "./a%20b.png"), or nil for one that
// leaves it ("../a.png"), an absolute path or a file: URL. Taken from the
// reference, not the resolved path, so it holds with either separator.
static NSString *OMDShareBundleRelativeName(NSString *reference)
{
    if ([reference hasPrefix:@"/"] || [reference hasPrefix:@"~"] ||
        [reference rangeOfString:@":"].location != NSNotFound ||
        [reference rangeOfString:@"\\"].location != NSNotFound) {
        return nil;
    }
    NSRange cut = [reference rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    NSString *path = (cut.location != NSNotFound ? [reference substringToIndex:cut.location] : reference);
    NSString *decoded = [path stringByRemovingPercentEncoding];
    if (decoded != nil) {
        path = decoded;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if ([part isEqualToString:@".."]) {
            return nil;
        }
        if ([part length] > 0 && ![part isEqualToString:@"."]) {
            [parts addObject:part];
        }
    }
    return [parts count] > 0 ? [parts componentsJoinedByString:@"/"] : nil;
}

static NSString *OMDShareBundleUniqueName(NSString *fileName, NSArray *names, NSString *prefix)
{
    NSString *stem = [fileName stringByDeletingPathExtension];
    NSString *extension = [fileName pathExtension];
    NSString *candidate = [prefix stringByAppendingString:fileName];
    NSUInteger attempt = 2;
    while ([names containsObject:candidate]) {
        NSString *numbered = [NSString stringWithFormat:@"%@-%lu", stem, (unsigned long)attempt++];
        if ([extension length] > 0) {
            numbered = [numbered stringByAppendingPathExtension:extension];
        }
        candidate = [prefix stringByAppendingString:numbered];
    }
    return candidate;
}

// Points every use of reference in the Markdown at replacement: ![](..)
// (with or without angle brackets, before a title or the closing
// parenthesis) and <img src="..">.
static void OMDShareBundleRewrite(NSMutableString *markdown, NSString *reference, NSString *replacement)
{
    BOOL needsBrackets = ([replacement rangeOfString:@" "].location != NSNotFound);
    NSString *destination = needsBrackets ? [NSString stringWithFormat:@"<%@>", replacement] : replacement;
    NSString *escaped = [NSRegularExpression escapedPatternForString:reference];
    NSString *pattern = [NSString stringWithFormat:@"\\]\\((?:<%@>|%@(?=[\\s)]))", escaped, escaped];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSString *template = [NSRegularExpression escapedTemplateForString:
        [NSString stringWithFormat:@"](%@", destination]];
    [expression replaceMatchesInString:markdown options:0 range:NSMakeRange(0, [markdown length])
                          withTemplate:template];
    NSArray *quotes = [NSArray arrayWithObjects:@"\"", @"'", nil];
    for (NSString *quote in quotes) {
        [markdown replaceOccurrencesOfString:[NSString stringWithFormat:@"src=%@%@%@", quote, reference, quote]
                                  withString:[NSString stringWithFormat:@"src=%@%@%@", quote, replacement, quote]
                                     options:0
                                       range:NSMakeRange(0, [markdown length])];
    }
}

void OMDShareBundleEntries(NSString *markdown,
                           NSString *baseDirectory,
                           NSString *baseName,
                           NSMutableArray *names,
                           NSMutableArray *contents)
{
    NSString *folder = [([baseName length] > 0 ? baseName : @"Document") stringByAppendingString:@"/"];
    NSMutableString *rewritten = [NSMutableString stringWithString:(markdown != nil ? markdown : @"")];
    NSMutableArray *imageNames = [NSMutableArray array];
    NSMutableArray *imageContents = [NSMutableArray array];
    NSMutableDictionary *namesByPath = [NSMutableDictionary dictionary];

    for (NSString *reference in OMDShareLocalImageReferences(markdown)) {
        NSString *path = OMDShareResolvedLocalPath(reference, baseDirectory);
        NSData *data = (path != nil ? [NSData dataWithContentsOfFile:path] : nil);
        if (data == nil) {
            continue;
        }
        NSString *relative = OMDShareBundleRelativeName(reference);
        NSString *kept = (relative != nil ? [folder stringByAppendingString:relative] : nil);
        NSString *name = [namesByPath objectForKey:path];
        if (name == nil) {
            // A relative reference keeps its name unless another image took
            // it; anything else goes in images/.
            name = (kept != nil && ![imageNames containsObject:kept]
                    ? kept
                    : OMDShareBundleUniqueName([path lastPathComponent], imageNames,
                                               [folder stringByAppendingString:@"images/"]));
            [namesByPath setObject:name forKey:path];
            [imageNames addObject:name];
            [imageContents addObject:data];
        }
        if ([name isEqualToString:kept]) {
            continue;
        }
        OMDShareBundleRewrite(rewritten, reference, [name substringFromIndex:[folder length]]);
    }

    NSString *documentName = [folder stringByAppendingString:
        [([baseName length] > 0 ? baseName : @"Document") stringByAppendingPathExtension:@"md"]];
    [names addObject:documentName];
    [contents addObject:[rewritten dataUsingEncoding:NSUTF8StringEncoding]];
    [names addObjectsFromArray:imageNames];
    [contents addObjectsFromArray:imageContents];
}
