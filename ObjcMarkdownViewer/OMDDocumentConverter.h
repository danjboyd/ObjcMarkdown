// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>

extern NSString * const OMDDocumentConverterErrorDomain;

typedef NS_ENUM(NSInteger, OMDDocumentConverterErrorCode) {
    OMDDocumentConverterErrorUnsupportedFormat = 1,
    OMDDocumentConverterErrorBackendUnavailable = 2,
    OMDDocumentConverterErrorExecutionFailed = 3,
    OMDDocumentConverterErrorOutputReadFailed = 4
};

@interface OMDDocumentConverter : NSObject

+ (OMDDocumentConverter *)defaultConverter;
+ (BOOL)isSupportedExtension:(NSString *)extension;
+ (NSString *)missingBackendInstallMessage;

- (NSString *)backendName;
- (BOOL)canImportExtension:(NSString *)extension;
- (BOOL)canExportExtension:(NSString *)extension;
- (BOOL)importFileAtPath:(NSString *)path
                markdown:(NSString **)markdown
                   error:(NSError **)error;
- (BOOL)exportMarkdown:(NSString *)markdown
                toPath:(NSString *)path
                 error:(NSError **)error;

@end
