// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// What the explorer shows a file as.
typedef NS_ENUM(NSInteger, OMDExplorerFileKind) {
    OMDExplorerFileKindFolder = 0,
    // Opens as Markdown.
    OMDExplorerFileKindMarkdown = 1,
    // Converted to Markdown on open (.html, .docx, ...).
    OMDExplorerFileKindImportable = 2,
    // Anything else: shown, dimmed.
    OMDExplorerFileKindOther = 3
};

OMDExplorerFileKind OMDExplorerFileKindForPath(NSString *path, BOOL isDirectory);

// A file or folder in the explorer's tree. A folder reads its children
// the first time they are asked for and keeps them, so the same node
// stands for the same path until the folder is reloaded; reloading keeps
// the nodes of entries that are still there.
@interface OMDExplorerNode : NSObject
{
    NSString *_path;
    NSString *_name;
    BOOL _isDirectory;
    OMDExplorerFileKind _kind;
    OMDExplorerNode *_parent;
    NSArray *_allChildren;
    NSArray *_visibleChildren;
    BOOL _visibleChildrenShowHidden;
}

- (instancetype)initWithPath:(NSString *)path isDirectory:(BOOL)isDirectory parent:(OMDExplorerNode *)parent;

- (NSString *)path;
- (NSString *)name;
- (BOOL)isDirectory;
- (OMDExplorerFileKind)kind;
// Not retained.
- (OMDExplorerNode *)parent;

// Folders first, then files, each in case-insensitive name order; names
// starting with "." only when showHidden. Empty for a file.
- (NSArray *)childrenShowingHidden:(BOOL)showHidden;
- (BOOL)hasLoadedChildren;
// Reads the folder again, and the folders below it whose children were
// read, reusing the nodes of entries still there.
- (void)reloadChildren;

// The node for path at or below this one, reading folders on the way;
// nil when path isn't below this node or doesn't exist. Hidden entries
// are found whatever the setting.
- (OMDExplorerNode *)descendantForPath:(NSString *)path;

@end
