// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// The work tree of the git repository holding the folder: the nearest
// folder, itself included, with a .git entry (a folder, or a file in
// worktrees and submodules). nil when the folder is in no repository.
NSString *OMDGitWorkTreeForDirectory(NSString *directory);

// The folder the explorer shows for a document: its repository's work
// tree, or its own folder when it is in none. nil without a path or when
// the document's folder doesn't exist.
NSString *OMDExplorerRootForDocumentPath(NSString *documentPath);
