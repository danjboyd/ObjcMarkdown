// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDWindowsClipboard.h"

// Built everywhere so the unit tests can check the CF_HTML layout; only
// Windows touches a clipboard.
NSData *OMDWindowsClipboardHTMLData(NSString *htmlFragment)
{
    NSData *fragment = [(htmlFragment != nil ? htmlFragment : @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSData *prefix = [@"<html><body>\r\n<!--StartFragment-->" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *suffix = [@"<!--EndFragment-->\r\n</body>\r\n</html>" dataUsingEncoding:NSUTF8StringEncoding];
    // Ten-digit offsets keep the header's length fixed while it's filled in.
    NSString *headerFormat = @"Version:0.9\r\nStartHTML:%010lu\r\nEndHTML:%010lu\r\nStartFragment:%010lu\r\nEndFragment:%010lu\r\n";
    NSUInteger headerLength = [[NSString stringWithFormat:headerFormat, 0UL, 0UL, 0UL, 0UL] length];
    unsigned long startHTML = (unsigned long)headerLength;
    unsigned long startFragment = startHTML + (unsigned long)[prefix length];
    unsigned long endFragment = startFragment + (unsigned long)[fragment length];
    unsigned long endHTML = endFragment + (unsigned long)[suffix length];
    NSString *header = [NSString stringWithFormat:headerFormat, startHTML, endHTML, startFragment, endFragment];

    NSMutableData *data = [NSMutableData dataWithData:[header dataUsingEncoding:NSASCIIStringEncoding]];
    [data appendData:prefix];
    [data appendData:fragment];
    [data appendData:suffix];
    char terminator = 0;
    [data appendBytes:&terminator length:1];
    return data;
}

#if defined(_WIN32)
#include <windows.h>
// GNUstep's headers undefine windows.h's "interface"; shlobj.h (DROPFILES,
// CFSTR_PREFERREDDROPEFFECT) needs it.
#define interface struct
#include <shlobj.h>
#undef interface

static BOOL OMDClipboardPut(UINT format, const void *bytes, size_t length)
{
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, length);
    if (memory == NULL) {
        return NO;
    }
    void *target = GlobalLock(memory);
    if (target == NULL) {
        GlobalFree(memory);
        return NO;
    }
    memcpy(target, bytes, length);
    GlobalUnlock(memory);
    if (SetClipboardData(format, memory) == NULL) {
        GlobalFree(memory);
        return NO;
    }
    return YES;
}

static BOOL OMDClipboardPutText(NSString *text)
{
    NSUInteger length = [text length];
    unichar *characters = calloc(length + 1, sizeof(unichar));
    if (characters == NULL) {
        return NO;
    }
    [text getCharacters:characters range:NSMakeRange(0, length)];
    BOOL put = OMDClipboardPut(CF_UNICODETEXT, characters, (length + 1) * sizeof(unichar));
    free(characters);
    return put;
}

// Another app may hold the clipboard for a moment; try a few times.
static BOOL OMDOpenClipboard(void)
{
    for (int attempt = 0; attempt < 10; attempt++) {
        if (OpenClipboard(NULL)) {
            return YES;
        }
        Sleep(20);
    }
    return NO;
}

BOOL OMDWindowsClipboardWriteRichText(NSString *plain, NSString *htmlFragment, NSData *rtf)
{
    if (!OMDOpenClipboard()) {
        return NO;
    }
    EmptyClipboard();
    BOOL wrote = NO;
    if (htmlFragment != nil) {
        UINT htmlFormat = RegisterClipboardFormatW(L"HTML Format");
        NSData *html = OMDWindowsClipboardHTMLData(htmlFragment);
        if (htmlFormat != 0 && OMDClipboardPut(htmlFormat, [html bytes], [html length])) {
            wrote = YES;
        }
    }
    if (rtf != nil && [rtf length] > 0) {
        UINT rtfFormat = RegisterClipboardFormatW(L"Rich Text Format");
        NSMutableData *terminated = [NSMutableData dataWithData:rtf];
        char terminator = 0;
        [terminated appendBytes:&terminator length:1];
        if (rtfFormat != 0 && OMDClipboardPut(rtfFormat, [terminated bytes], [terminated length])) {
            wrote = YES;
        }
    }
    if (plain != nil && OMDClipboardPutText(plain)) {
        wrote = YES;
    }
    CloseClipboard();
    return wrote;
}

BOOL OMDWindowsClipboardWriteFiles(NSArray *paths)
{
    if ([paths count] == 0) {
        return NO;
    }
    // DROPFILES, then each path as a NUL-terminated wide string, then one
    // more NUL.
    NSMutableData *list = [NSMutableData data];
    NSMutableString *text = [NSMutableString string];
    unichar nul = 0;
    for (NSString *path in paths) {
        NSString *windowsPath = [path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
        NSUInteger length = [windowsPath length];
        unichar *characters = calloc(length + 1, sizeof(unichar));
        if (characters == NULL) {
            return NO;
        }
        [windowsPath getCharacters:characters range:NSMakeRange(0, length)];
        [list appendBytes:characters length:(length + 1) * sizeof(unichar)];
        free(characters);
        if ([text length] > 0) {
            [text appendString:@"\r\n"];
        }
        [text appendString:windowsPath];
    }
    [list appendBytes:&nul length:sizeof(nul)];

    NSMutableData *drop = [NSMutableData dataWithLength:sizeof(DROPFILES)];
    DROPFILES *header = (DROPFILES *)[drop mutableBytes];
    header->pFiles = sizeof(DROPFILES);
    header->fWide = TRUE;
    [drop appendData:list];

    if (!OMDOpenClipboard()) {
        return NO;
    }
    EmptyClipboard();
    BOOL wrote = OMDClipboardPut(CF_HDROP, [drop bytes], [drop length]);
    if (wrote) {
        UINT effectFormat = RegisterClipboardFormatW(L"Preferred DropEffect");
        DWORD effect = DROPEFFECT_COPY;
        if (effectFormat != 0) {
            OMDClipboardPut(effectFormat, &effect, sizeof(effect));
        }
        OMDClipboardPutText(text);
    }
    CloseClipboard();
    return wrote;
}

#else

BOOL OMDWindowsClipboardWriteRichText(NSString *plain, NSString *htmlFragment, NSData *rtf)
{
    (void)plain;
    (void)htmlFragment;
    (void)rtf;
    return NO;
}

BOOL OMDWindowsClipboardWriteFiles(NSArray *paths)
{
    (void)paths;
    return NO;
}

#endif
