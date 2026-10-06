// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDExplorerRoot.h"

NSString *OMDGitWorkTreeForDirectory(NSString *directory)
{
    if (directory == nil || [directory length] == 0 || ![directory isAbsolutePath]) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *candidate = [directory stringByStandardizingPath];
    while ([candidate length] > 0) {
        if ([fileManager fileExistsAtPath:[candidate stringByAppendingPathComponent:@".git"]]) {
            return candidate;
        }
        NSString *parent = [candidate stringByDeletingLastPathComponent];
        if ([parent length] == 0 || [parent isEqualToString:candidate]) {
            break;
        }
        candidate = parent;
    }
    return nil;
}

NSString *OMDExplorerRootForDocumentPath(NSString *documentPath)
{
    if (documentPath == nil || [documentPath length] == 0 || ![documentPath isAbsolutePath]) {
        return nil;
    }

    NSString *folder = [[documentPath stringByStandardizingPath] stringByDeletingLastPathComponent];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&isDirectory] || !isDirectory) {
        return nil;
    }

    NSString *workTree = OMDGitWorkTreeForDirectory(folder);
    return (workTree != nil ? workTree : folder);
}
