// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareItem.h"

@implementation OMDShareItem

- (instancetype)initWithTitle:(NSString *)title
                       format:(OMDShareFormat)format
                      fileURL:(NSURL *)fileURL
                 renderedText:(NSAttributedString *)renderedText
{
    self = [super init];
    if (self != nil) {
        _title = [title copy];
        _format = format;
        _fileURL = [fileURL copy];
        _renderedText = [renderedText copy];
    }
    return self;
}

- (void)dealloc
{
    [_title release];
    [_fileURL release];
    [_renderedText release];
    [_documentURL release];
    [super dealloc];
}

- (NSString *)title
{
    return _title;
}

- (OMDShareFormat)format
{
    return _format;
}

- (NSURL *)fileURL
{
    return _fileURL;
}

- (NSAttributedString *)renderedText
{
    return _renderedText;
}

- (NSString *)fileName
{
    return [[_fileURL path] lastPathComponent];
}

- (NSURL *)documentURL
{
    return _documentURL;
}

- (void)setDocumentURL:(NSURL *)documentURL
{
    [_documentURL release];
    _documentURL = [documentURL copy];
}

- (NSURL *)folderURL
{
    return _documentURL != nil ? _documentURL : _fileURL;
}

@end
