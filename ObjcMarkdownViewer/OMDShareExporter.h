// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>
#import "OMDShareItem.h"

@class OMDDocumentConverter;

extern NSString * const OMDShareErrorDomain;

typedef NS_ENUM(NSInteger, OMDShareErrorCode) {
    OMDShareErrorNoDocument = 1,
    OMDShareErrorTemporaryDirectory = 2,
    OMDShareErrorWriteFailed = 3,
    OMDShareErrorConverterUnavailable = 4
};

// The document being shared, as the exporter needs it. The window
// controller answers for the document in front; tests use a stand-in.
@protocol OMDShareSource <NSObject>
// The document's name without its extension ("Q3 Plan"), or nil.
- (NSString *)shareBaseName;
// The current buffer, unsaved edits included, as it is.
- (NSString *)shareSourceText;
// The extension the source is saved with ("md", or "txt" for a text file).
- (NSString *)shareSourceExtension;
// The buffer as Markdown for the converters (a code file fenced).
- (NSString *)shareMarkdownText;
// Where relative images resolve, or nil.
- (NSString *)shareResourceDirectory;
// The rendered document for a reader (default theme, 100%), or nil.
- (NSAttributedString *)shareRenderedText;
// Writes the PDF the app prints (Export as PDF) to path.
- (BOOL)shareWritePDFToPath:(NSString *)path;
// The Pandoc converter, or nil when Pandoc isn't there.
- (OMDDocumentConverter *)documentConverter;
@optional
// The selection (#192), or nil when nothing is selected: as it is in the
// source (a Markdown share), and as Markdown (the converters, the PDF,
// Copy Rendered; a code file's selection fenced). A preview selection
// grows to whole blocks (OMDShareMarkdownForPreviewRange()).
- (NSString *)shareSelectedSourceText;
- (NSString *)shareSelectedMarkdownText;
// The rendered text and the PDF of other Markdown than the document's.
- (NSAttributedString *)shareRenderedTextForMarkdown:(NSString *)markdown;
- (BOOL)shareWritePDFForMarkdown:(NSString *)markdown toPath:(NSString *)path;
@end

// Exports the current document to a temporary file in a share format,
// with no panel. The files live in a directory of this launch (0700); they
// are never deleted when a share returns, since Mail, Messages or AirDrop
// read them later. Earlier launches' directories are swept at launch.
@interface OMDShareExporter : NSObject
{
    id<OMDShareSource> _source;
}

+ (NSString *)fileExtensionForFormat:(OMDShareFormat)format;
// "PDF", "Word Document", "Markdown File", "HTML".
+ (NSString *)displayNameForFormat:(OMDShareFormat)format;
// Whether the format needs Pandoc.
+ (BOOL)formatNeedsConverter:(OMDShareFormat)format;
// A file name safe on every platform, from a document's name.
+ (NSString *)safeFileBaseName:(NSString *)name;

// The directory under which each launch keeps its exports.
+ (NSString *)temporaryRootDirectory;
// This launch's directory, created (0700) on first use.
+ (NSString *)launchTemporaryDirectory;
// Removes the directories of launches that are over (their process is
// gone, or a day has passed), never this launch's.
+ (void)sweepStaleTemporaryDirectories;

// The source is not retained.
- (instancetype)initWithSource:(id<OMDShareSource>)source;

// Exports the current buffer in format, to a new directory of its own in
// this launch's directory so the file keeps the document's name.
- (OMDShareItem *)shareItemForFormat:(OMDShareFormat)format error:(NSError **)error;

// Whether the source has a selection to share.
- (BOOL)hasSelection;
// The same as -shareItemForFormat:error: and its completion form, for the
// selection only when selectionOnly is YES (an error if nothing is
// selected).
- (OMDShareItem *)shareItemForFormat:(OMDShareFormat)format
                       selectionOnly:(BOOL)selectionOnly
                               error:(NSError **)error;
- (void)shareItemForFormat:(OMDShareFormat)format
             selectionOnly:(BOOL)selectionOnly
                completion:(void (^)(OMDShareItem *item, NSError *error))completion;

// The same, without blocking the window for Word and HTML: what the export
// needs from the document is read here, Pandoc converts on a background
// queue, and completion runs on the main thread with the item or the error.
// Markdown and PDF (which prints on the main thread) complete before this
// returns.
- (void)shareItemForFormat:(OMDShareFormat)format
                completion:(void (^)(OMDShareItem *item, NSError *error))completion;

@end
