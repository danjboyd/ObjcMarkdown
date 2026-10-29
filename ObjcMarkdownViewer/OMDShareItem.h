// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// The forms a document is shared in (docs/share-design.md). The values are
// stored as the last-used format, so don't renumber them.
typedef NS_ENUM(NSInteger, OMDShareFormat) {
    OMDShareFormatPDF = 0,
    OMDShareFormatWord = 1,      // .docx, through Pandoc
    OMDShareFormatMarkdown = 2,  // the source as it is (a .txt stays .txt)
    OMDShareFormatHTML = 3
};

// What is shared: the document's title, the format and the exported file,
// and the rendered text where the presenter can use it (a rich email body).
@interface OMDShareItem : NSObject
{
    NSString *_title;
    OMDShareFormat _format;
    NSURL *_fileURL;
    NSAttributedString *_renderedText;
    NSURL *_documentURL;
}

- (instancetype)initWithTitle:(NSString *)title
                       format:(OMDShareFormat)format
                      fileURL:(NSURL *)fileURL
                 renderedText:(NSAttributedString *)renderedText;

// "Q3 Plan": the document's name without its extension.
- (NSString *)title;
- (OMDShareFormat)format;
// The exported file, named after the document ("Q3 Plan.pdf").
- (NSURL *)fileURL;
// The rendered document, or nil.
- (NSAttributedString *)renderedText;
// The exported file's name ("Q3 Plan.pdf").
- (NSString *)fileName;
// The document's own file when the exported file is a copy of it as saved
// (a Markdown share of an unedited document), or nil (#265).
- (NSURL *)documentURL;
- (void)setDocumentURL:(NSURL *)documentURL;
// What Show in Folder selects: the document, or else the exported file.
- (NSURL *)folderURL;

@end
