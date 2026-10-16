// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>
#import "OMDShareItem.h"

// What a colleague won't get when the document is shared as it is
// (docs/share-design.md, #190).
typedef NS_ENUM(NSInteger, OMDShareWarningKind) {
    // Images on this computer: relative or absolute paths and file:// URLs,
    // in ![]() and <img src>.
    OMDShareWarningLocalImages = 1,
    // Local images that aren't there even here.
    OMDShareWarningMissingImages = 2,
    // Links to files on this computer: file:// URLs, and relative or
    // absolute paths to files that exist.
    OMDShareWarningLocalLinks = 3,
    // $...$ or $$...$$ formulas, by the renderer's rules.
    OMDShareWarningMath = 4,
    // ```mermaid diagrams.
    OMDShareWarningMermaid = 5
};

@interface OMDShareWarning : NSObject
{
    OMDShareWarningKind _kind;
    NSArray *_references;
    NSArray *_resolvedPaths;
    NSArray *_htmlReferences;
}

- (OMDShareWarningKind)kind;
// One sentence for the share sheet or an alert, for a share in format (a
// Word file loses only the images written as <img>).
- (NSString *)messageForFormat:(OMDShareFormat)format;
// The URLs or paths as the document writes them, in document order, each
// once; empty for math and Mermaid.
- (NSArray *)references;
// The absolute paths of those that exist on this computer.
- (NSArray *)resolvedPaths;
// The images among the references written as raw HTML (<img src>), which
// Pandoc leaves out of a Word file.
- (NSArray *)htmlReferences;
// Whether a share in format loses what this warning is about.
- (BOOL)appliesToFormat:(OMDShareFormat)format;
// Whether a PDF would carry it (images, math and diagrams are drawn in).
- (BOOL)suggestsPDF;
// Whether a .zip of the Markdown with its images would carry it (local
// images; offered for a Markdown share).
- (BOOL)offersBundle;

@end

// Every warning for the document, in the kind order above, or an empty
// array. baseDirectory is where relative paths resolve (nil: they are
// local but can't be checked, so images count as missing and relative
// links aren't reported). Code spans and code blocks are skipped.
NSArray *OMDShareWarnings(NSString *markdown, NSString *baseDirectory);
// The warnings that apply to a share in format.
NSArray *OMDShareWarningsForFormat(NSArray *warnings, OMDShareFormat format);

// The local image references of the document, in document order, each
// once, as written (what a .zip bundle collects).
NSArray *OMDShareLocalImageReferences(NSString *markdown);
// The absolute path a local reference resolves to, or nil for a remote URL,
// an in-document anchor or a relative path without a base directory.
NSString *OMDShareResolvedLocalPath(NSString *reference, NSString *baseDirectory);
