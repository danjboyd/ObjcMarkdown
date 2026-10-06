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

NSArray *OMDExplorerRecentRootsAdding(NSArray *recent, NSString *root, NSUInteger limit)
{
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *candidates = [NSMutableArray array];
    if ([root length] > 0) {
        [candidates addObject:root];
    }
    for (id path in recent) {
        if ([path isKindOfClass:[NSString class]] && [path length] > 0) {
            [candidates addObject:path];
        }
    }
    for (NSString *path in candidates) {
        NSString *standardized = [path stringByStandardizingPath];
        if ([seen containsObject:standardized] || [result count] >= limit) {
            continue;
        }
        [seen addObject:standardized];
        [result addObject:standardized];
    }
    return result;
}

NSArray *OMDExplorerRootMenuTitles(NSArray *roots)
{
    NSCountedSet *names = [NSCountedSet set];
    for (NSString *root in roots) {
        [names addObject:[root lastPathComponent]];
    }
    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:[roots count]];
    for (NSString *root in roots) {
        NSString *name = [root lastPathComponent];
        if ([names countForObject:name] > 1) {
            NSString *parent = [[root stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath];
            [titles addObject:[NSString stringWithFormat:@"%@ (%@)", name, parent]];
        } else {
            [titles addObject:name];
        }
    }
    return titles;
}
