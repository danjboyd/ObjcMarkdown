// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDDocumentConverter.h"
#import "OMDPandocConverter.h"

NSString * const OMDDocumentConverterErrorDomain = @"OMDDocumentConverterErrorDomain";

static NSSet *OMDSupportedExtensions(void)
{
    static NSSet *extensions = nil;
    if (extensions == nil) {
        extensions = [[NSSet alloc] initWithObjects:@"rtf", @"docx", @"odt", @"html", @"htm", nil];
    }
    return extensions;
}

@implementation OMDDocumentConverter

+ (OMDDocumentConverter *)defaultConverter
{
    return [OMDPandocConverter converterIfAvailable];
}

+ (BOOL)isSupportedExtension:(NSString *)extension
{
    if (extension == nil || [extension length] == 0) {
        return NO;
    }
    return [OMDSupportedExtensions() containsObject:[extension lowercaseString]];
}

+ (NSString *)missingBackendInstallMessage
{
    return @"Pandoc is required for DOCX/ODT/RTF/HTML import and export.\n"
           @"Install with: sudo apt-get install pandoc";
}

- (NSString *)backendName
{
    return @"unknown";
}

- (BOOL)canImportExtension:(NSString *)extension
{
    return NO;
}

- (BOOL)canExportExtension:(NSString *)extension
{
    return NO;
}

- (BOOL)importFileAtPath:(NSString *)path
                markdown:(NSString **)markdown
                   error:(NSError **)error
{
    if (error != NULL) {
        *error = [NSError errorWithDomain:OMDDocumentConverterErrorDomain
                                     code:OMDDocumentConverterErrorBackendUnavailable
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: @"No document converter backend is available."
                                 }];
    }
    return NO;
}

- (BOOL)exportMarkdown:(NSString *)markdown
                toPath:(NSString *)path
                 error:(NSError **)error
{
    if (error != NULL) {
        *error = [NSError errorWithDomain:OMDDocumentConverterErrorDomain
                                     code:OMDDocumentConverterErrorBackendUnavailable
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: @"No document converter backend is available."
                                 }];
    }
    return NO;
}

@end
