// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import "OMDPandocConverter.h"

@interface OMDPandocConverter ()
{
    NSString *_pandocPath;
}
- (NSString *)pandocFormatForExtension:(NSString *)extension;
- (NSString *)temporaryPathWithPrefix:(NSString *)prefix extension:(NSString *)extension;
- (BOOL)runPandocWithArguments:(NSArray *)arguments
                       logText:(NSString **)logText
              terminationStatus:(int *)terminationStatus
                    launchError:(NSError **)launchError;
- (NSError *)conversionErrorWithDescription:(NSString *)description
                                     reason:(NSString *)reason
                                       code:(OMDDocumentConverterErrorCode)code;
- (NSString *)trimmedLogText:(NSString *)text;
@end

static NSString *OMDExecutablePathNamed(NSString *name)
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *pathValue = [environment objectForKey:@"PATH"];
    if (pathValue == nil || [pathValue length] == 0) {
        return nil;
    }

    NSArray *searchPaths = [pathValue componentsSeparatedByString:@":"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *searchPath in searchPaths) {
        if (searchPath == nil || [searchPath length] == 0) {
            continue;
        }
        NSString *candidate = [searchPath stringByAppendingPathComponent:name];
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }

    return nil;
}

static NSString *OMDResolvePandocPath(void)
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *overridePath = [environment objectForKey:@"OMD_PANDOC_PATH"];
    if (overridePath != nil && [overridePath length] > 0) {
        NSString *expanded = [overridePath stringByExpandingTildeInPath];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:expanded]) {
            return expanded;
        }
    }

    NSString *pathValue = OMDExecutablePathNamed(@"pandoc");
    if (pathValue != nil) {
        return pathValue;
    }

    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/pandoc"]) {
        return @"/usr/bin/pandoc";
    }

    return nil;
}

@implementation OMDPandocConverter

+ (OMDPandocConverter *)converterIfAvailable
{
    NSString *pandocPath = OMDResolvePandocPath();
    if (pandocPath == nil) {
        return nil;
    }
    return [[[OMDPandocConverter alloc] initWithPandocPath:pandocPath] autorelease];
}

- (id)initWithPandocPath:(NSString *)pandocPath
{
    self = [super init];
    if (self != nil) {
        _pandocPath = [pandocPath copy];
    }
    return self;
}

- (void)dealloc
{
    [_pandocPath release];
    [super dealloc];
}

- (NSString *)backendName
{
    return @"pandoc";
}

- (BOOL)canImportExtension:(NSString *)extension
{
    return [OMDDocumentConverter isSupportedExtension:extension];
}

- (BOOL)canExportExtension:(NSString *)extension
{
    return [OMDDocumentConverter isSupportedExtension:extension];
}

- (NSError *)conversionErrorWithDescription:(NSString *)description
                                     reason:(NSString *)reason
                                       code:(OMDDocumentConverterErrorCode)code
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (description != nil) {
        [userInfo setObject:description forKey:NSLocalizedDescriptionKey];
    }
    if (reason != nil && [reason length] > 0) {
        [userInfo setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
    }

    return [NSError errorWithDomain:OMDDocumentConverterErrorDomain
                               code:code
                           userInfo:userInfo];
}

- (NSString *)temporaryPathWithPrefix:(NSString *)prefix extension:(NSString *)extension
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory == nil || [temporaryDirectory length] == 0) {
        temporaryDirectory = @"/tmp";
    }

    NSString *fileName = [NSString stringWithFormat:@"%@-%@.%@",
                          prefix,
                          [[NSProcessInfo processInfo] globallyUniqueString],
                          extension];
    return [temporaryDirectory stringByAppendingPathComponent:fileName];
}

- (NSString *)pandocFormatForExtension:(NSString *)extension
{
    NSString *lower = [extension lowercaseString];
    if ([lower isEqualToString:@"rtf"]) {
        return @"rtf";
    }
    if ([lower isEqualToString:@"docx"]) {
        return @"docx";
    }
    if ([lower isEqualToString:@"odt"]) {
        return @"odt";
    }
    if ([lower isEqualToString:@"html"] || [lower isEqualToString:@"htm"]) {
        return @"html";
    }
    return nil;
}

- (NSString *)trimmedLogText:(NSString *)text
{
    if (text == nil) {
        return nil;
    }
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    return [text stringByTrimmingCharactersInSet:whitespace];
}

- (BOOL)runPandocWithArguments:(NSArray *)arguments
                       logText:(NSString **)logText
              terminationStatus:(int *)terminationStatus
                    launchError:(NSError **)launchError
{
    NSString *logPath = [self temporaryPathWithPrefix:@"objcmarkdown-pandoc-log"
                                            extension:@"txt"];
    [[NSFileManager defaultManager] createFileAtPath:logPath
                                            contents:nil
                                          attributes:nil];
    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:_pandocPath];
    [task setArguments:arguments];
    if (logHandle != nil) {
        [task setStandardOutput:logHandle];
        [task setStandardError:logHandle];
    }

    BOOL launched = YES;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        launched = NO;
        if (launchError != NULL) {
            *launchError = [self conversionErrorWithDescription:@"Unable to launch pandoc."
                                                         reason:[exception reason]
                                                           code:OMDDocumentConverterErrorExecutionFailed];
        }
    }

    if (logHandle != nil) {
        [logHandle closeFile];
    }

    NSString *capturedLog = [NSString stringWithContentsOfFile:logPath
                                                      encoding:NSUTF8StringEncoding
                                                         error:NULL];
    NSString *trimmedLog = [self trimmedLogText:capturedLog];
    if (logText != NULL) {
        *logText = trimmedLog;
    }

    if (terminationStatus != NULL) {
        *terminationStatus = launched ? [task terminationStatus] : -1;
    }

    [[NSFileManager defaultManager] removeItemAtPath:logPath error:NULL];
    return launched && [task terminationStatus] == 0;
}

- (BOOL)importFileAtPath:(NSString *)path
                markdown:(NSString **)markdown
                   error:(NSError **)error
{
    NSString *extension = [[path pathExtension] lowercaseString];
    NSString *sourceFormat = [self pandocFormatForExtension:extension];
    if (sourceFormat == nil) {
        if (error != NULL) {
            *error = [self conversionErrorWithDescription:@"Unsupported import format."
                                                   reason:@"Choose an .html, .rtf, .docx, or .odt file."
                                                     code:OMDDocumentConverterErrorUnsupportedFormat];
        }
        return NO;
    }

    NSString *outputMarkdownPath = [self temporaryPathWithPrefix:@"objcmarkdown-import"
                                                       extension:@"md"];
    NSArray *arguments = [NSArray arrayWithObjects:
        @"--from", sourceFormat,
        @"--to", @"commonmark",
        @"--wrap=none",
        @"--output", outputMarkdownPath,
        path,
        nil];

    NSString *logText = nil;
    int status = 0;
    NSError *launchError = nil;
    BOOL success = [self runPandocWithArguments:arguments
                                        logText:&logText
                               terminationStatus:&status
                                     launchError:&launchError];
    if (!success) {
        [[NSFileManager defaultManager] removeItemAtPath:outputMarkdownPath error:NULL];
        if (error != NULL) {
            if (launchError != nil) {
                *error = launchError;
            } else {
                NSString *reason = ([logText length] > 0)
                    ? logText
                    : [NSString stringWithFormat:@"Pandoc exited with status %d.", status];
                *error = [self conversionErrorWithDescription:@"Import failed."
                                                       reason:reason
                                                         code:OMDDocumentConverterErrorExecutionFailed];
            }
        }
        return NO;
    }

    NSError *readError = nil;
    NSString *importedMarkdown = [NSString stringWithContentsOfFile:outputMarkdownPath
                                                            encoding:NSUTF8StringEncoding
                                                               error:&readError];
    [[NSFileManager defaultManager] removeItemAtPath:outputMarkdownPath error:NULL];

    if (importedMarkdown == nil) {
        if (error != NULL) {
            NSString *reason = [readError localizedDescription];
            *error = [self conversionErrorWithDescription:@"Import succeeded, but output could not be read."
                                                   reason:reason
                                                     code:OMDDocumentConverterErrorOutputReadFailed];
        }
        return NO;
    }

    if (markdown != NULL) {
        *markdown = importedMarkdown;
    }
    return YES;
}

- (BOOL)exportMarkdown:(NSString *)markdown
                toPath:(NSString *)path
                 error:(NSError **)error
{
    NSString *extension = [[path pathExtension] lowercaseString];
    NSString *targetFormat = [self pandocFormatForExtension:extension];
    if (targetFormat == nil) {
        if (error != NULL) {
            *error = [self conversionErrorWithDescription:@"Unsupported export format."
                                                   reason:@"Choose an .html, .rtf, .docx, or .odt destination."
                                                     code:OMDDocumentConverterErrorUnsupportedFormat];
        }
        return NO;
    }

    NSString *inputMarkdownPath = [self temporaryPathWithPrefix:@"objcmarkdown-export"
                                                      extension:@"md"];
    NSError *writeError = nil;
    BOOL wroteInput = [(markdown != nil ? markdown : @"") writeToFile:inputMarkdownPath
                                                            atomically:YES
                                                              encoding:NSUTF8StringEncoding
                                                                 error:&writeError];
    if (!wroteInput) {
        if (error != NULL) {
            *error = [self conversionErrorWithDescription:@"Unable to prepare export input."
                                                   reason:[writeError localizedDescription]
                                                     code:OMDDocumentConverterErrorExecutionFailed];
        }
        return NO;
    }

    NSArray *arguments = [NSArray arrayWithObjects:
        @"--from", @"commonmark",
        @"--to", targetFormat,
        @"--wrap=none",
        @"--output", path,
        inputMarkdownPath,
        nil];

    NSString *logText = nil;
    int status = 0;
    NSError *launchError = nil;
    BOOL success = [self runPandocWithArguments:arguments
                                        logText:&logText
                               terminationStatus:&status
                                     launchError:&launchError];
    [[NSFileManager defaultManager] removeItemAtPath:inputMarkdownPath error:NULL];

    if (!success) {
        if (error != NULL) {
            if (launchError != nil) {
                *error = launchError;
            } else {
                NSString *reason = ([logText length] > 0)
                    ? logText
                    : [NSString stringWithFormat:@"Pandoc exited with status %d.", status];
                *error = [self conversionErrorWithDescription:@"Export failed."
                                                       reason:reason
                                                         code:OMDDocumentConverterErrorExecutionFailed];
            }
        }
        return NO;
    }

    return YES;
}

@end
