// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDTextFileSupport.h"

NSString *OMDTrimmedString(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSString *OMDDiskFingerprintForFileAttributes(NSDictionary *attributes)
{
    if (attributes == nil) {
        return nil;
    }

    NSDate *modificationDate = [attributes objectForKey:NSFileModificationDate];
    NSNumber *sizeValue = [attributes objectForKey:NSFileSize];
    NSNumber *inodeValue = [attributes objectForKey:NSFileSystemFileNumber];
    if (modificationDate == nil && sizeValue == nil && inodeValue == nil) {
        return nil;
    }

    NSTimeInterval modifiedAt = (modificationDate != nil
                                 ? [modificationDate timeIntervalSinceReferenceDate]
                                 : 0.0);
    unsigned long long size = [sizeValue respondsToSelector:@selector(unsignedLongLongValue)]
                              ? [sizeValue unsignedLongLongValue]
                              : 0ULL;
    unsigned long long inode = [inodeValue respondsToSelector:@selector(unsignedLongLongValue)]
                               ? [inodeValue unsignedLongLongValue]
                               : 0ULL;
    return [NSString stringWithFormat:@"%.6f:%llu:%llu",
                                      modifiedAt,
                                      size,
                                      inode];
}

BOOL OMDIsMarkdownExtension(NSString *extension)
{
    if (extension == nil || [extension length] == 0) {
        return NO;
    }
    NSString *lower = [extension lowercaseString];
    return [lower isEqualToString:@"md"] ||
           [lower isEqualToString:@"markdown"] ||
           [lower isEqualToString:@"mdown"];
}

static BOOL OMDIsPlainTextNoHighlightExtension(NSString *extension)
{
    if (extension == nil || [extension length] == 0) {
        return NO;
    }
    NSString *lower = [extension lowercaseString];
    return [lower isEqualToString:@"txt"] ||
           [lower isEqualToString:@"text"] ||
           [lower isEqualToString:@"log"];
}

NSString *OMDVerbatimSyntaxTokenForExtension(NSString *extension)
{
    NSString *lower = [[OMDTrimmedString(extension) lowercaseString] copy];
    if ([lower length] == 0 || OMDIsPlainTextNoHighlightExtension(lower)) {
        [lower release];
        return nil;
    }

    NSString *token = lower;
    if ([lower isEqualToString:@"yml"]) {
        token = @"yaml";
    } else if ([lower isEqualToString:@"py"]) {
        token = @"python";
    } else if ([lower isEqualToString:@"zsh"]) {
        token = @"bash";
    } else if ([lower isEqualToString:@"htm"]) {
        token = @"html";
    }

    NSString *result = [token copy];
    [lower release];
    return [result autorelease];
}

static NSUInteger OMDMaxBacktickRunLength(NSString *text)
{
    if (text == nil || [text length] == 0) {
        return 0;
    }

    NSUInteger longest = 0;
    NSUInteger run = 0;
    NSUInteger length = [text length];
    NSUInteger index = 0;
    for (; index < length; index++) {
        unichar ch = [text characterAtIndex:index];
        if (ch == '`') {
            run += 1;
            if (run > longest) {
                longest = run;
            }
        } else {
            run = 0;
        }
    }
    return longest;
}

static NSString *OMDBacktickFenceString(NSUInteger length)
{
    if (length < 3) {
        length = 3;
    }
    NSMutableString *fence = [NSMutableString stringWithCapacity:length];
    NSUInteger index = 0;
    for (; index < length; index++) {
        [fence appendString:@"`"];
    }
    return fence;
}

NSString *OMDMarkdownCodeFenceWrappedText(NSString *text, NSString *languageToken)
{
    NSString *payload = (text != nil ? text : @"");
    NSUInteger fenceLength = OMDMaxBacktickRunLength(payload) + 1;
    if (fenceLength < 3) {
        fenceLength = 3;
    }
    NSString *fence = OMDBacktickFenceString(fenceLength);
    NSString *language = OMDTrimmedString(languageToken);

    NSMutableString *wrapped = [NSMutableString string];
    [wrapped appendString:fence];
    if ([language length] > 0) {
        [wrapped appendString:language];
    }
    [wrapped appendString:@"\n"];
    [wrapped appendString:payload];
    if (![payload hasSuffix:@"\n"]) {
        [wrapped appendString:@"\n"];
    }
    [wrapped appendString:fence];
    return wrapped;
}

// The Unicode encoding named by a byte-order mark at the start of the data,
// and the mark's length; returns NO when there is no mark.
static BOOL OMDByteOrderMarkEncoding(NSData *data, NSStringEncoding *encodingOut, NSUInteger *markLengthOut)
{
    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger length = [data length];
    NSStringEncoding encoding = 0;
    NSUInteger markLength = 0;

    // UTF-32 first: its little-endian mark starts with UTF-16's.
    if (length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00) {
        encoding = NSUTF32LittleEndianStringEncoding;
        markLength = 4;
    } else if (length >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF) {
        encoding = NSUTF32BigEndianStringEncoding;
        markLength = 4;
    } else if (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        encoding = NSUTF8StringEncoding;
        markLength = 3;
    } else if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        encoding = NSUTF16LittleEndianStringEncoding;
        markLength = 2;
    } else if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        encoding = NSUTF16BigEndianStringEncoding;
        markLength = 2;
    } else {
        return NO;
    }

    if (encodingOut != NULL) {
        *encodingOut = encoding;
    }
    if (markLengthOut != NULL) {
        *markLengthOut = markLength;
    }
    return YES;
}

BOOL OMDDataAppearsBinary(NSData *data)
{
    if (data == nil || [data length] == 0) {
        return NO;
    }
    // UTF-16 and UTF-32 text is full of NUL bytes; trust its byte-order mark.
    NSStringEncoding markedEncoding = 0;
    if (OMDByteOrderMarkEncoding(data, &markedEncoding, NULL) &&
        markedEncoding != NSUTF8StringEncoding) {
        return NO;
    }

    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger sampleLength = [data length];
    if (sampleLength > 8192) {
        sampleLength = 8192;
    }
    NSUInteger controlCount = 0;
    NSUInteger index = 0;
    for (; index < sampleLength; index++) {
        unsigned char value = bytes[index];
        if (value == 0) {
            return YES;
        }
        if (value < 0x09 || (value > 0x0D && value < 0x20)) {
            controlCount += 1;
        }
    }

    return controlCount > ((sampleLength / 16) + 1);
}

NSString *OMDDecodeTextFromData(NSData *data, NSStringEncoding *usedEncodingOut)
{
    if (data == nil) {
        return nil;
    }
    if ([data length] == 0) {
        if (usedEncodingOut != NULL) {
            *usedEncodingOut = NSUTF8StringEncoding;
        }
        return @"";
    }

    // A byte-order mark decides the encoding; the mark itself isn't text.
    NSStringEncoding markedEncoding = 0;
    NSUInteger markLength = 0;
    if (OMDByteOrderMarkEncoding(data, &markedEncoding, &markLength)) {
        NSData *payload = [data subdataWithRange:NSMakeRange(markLength, [data length] - markLength)];
        NSString *decoded = [[[NSString alloc] initWithData:payload encoding:markedEncoding] autorelease];
        if (decoded != nil) {
            if (usedEncodingOut != NULL) {
                *usedEncodingOut = markedEncoding;
            }
            return decoded;
        }
    }

    // Without a mark: UTF-8 if it is valid, else a single-byte encoding.
    // (UTF-16 isn't guessed: GNUstep decodes any byte sequence as UTF-16.)
    // Windows-1252 rejects five undefined bytes; Latin-1 accepts everything.
    NSStringEncoding encodings[] = {
        NSUTF8StringEncoding,
        NSWindowsCP1252StringEncoding,
        NSISOLatin1StringEncoding
    };
    NSUInteger encodingCount = sizeof(encodings) / sizeof(encodings[0]);
    NSUInteger index = 0;
    for (; index < encodingCount; index++) {
        NSStringEncoding encoding = encodings[index];
        NSString *decoded = [[[NSString alloc] initWithData:data encoding:encoding] autorelease];
        if (decoded != nil) {
            if (usedEncodingOut != NULL) {
                *usedEncodingOut = encoding;
            }
            return decoded;
        }
    }
    return nil;
}

NSString *OMDNormalizedRelativePath(NSString *value)
{
    NSString *trimmed = OMDTrimmedString(value);
    if ([trimmed length] == 0) {
        return @"";
    }

    NSArray *components = [trimmed pathComponents];
    NSMutableArray *normalized = [NSMutableArray array];
    for (NSString *component in components) {
        if (component == nil || [component length] == 0 ||
            [component isEqualToString:@"/"] ||
            [component isEqualToString:@"."]) {
            continue;
        }
        if ([component isEqualToString:@".."]) {
            if ([normalized count] > 0) {
                [normalized removeLastObject];
            }
            continue;
        }
        [normalized addObject:component];
    }
    return [normalized componentsJoinedByString:@"/"];
}
