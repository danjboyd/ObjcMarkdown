// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDExplorerTree.h"
#import "OMDDocumentConverter.h"
#import "OMDTextFileSupport.h"

OMDExplorerFileKind OMDExplorerFileKindForPath(NSString *path, BOOL isDirectory)
{
    if (isDirectory) {
        return OMDExplorerFileKindFolder;
    }
    NSString *extension = [[path pathExtension] lowercaseString];
    if (OMDIsMarkdownExtension(extension)) {
        return OMDExplorerFileKindMarkdown;
    }
    if ([OMDDocumentConverter isSupportedExtension:extension]) {
        return OMDExplorerFileKindImportable;
    }
    return OMDExplorerFileKindOther;
}

@implementation OMDExplorerNode

- (instancetype)initWithPath:(NSString *)path isDirectory:(BOOL)isDirectory parent:(OMDExplorerNode *)parent
{
    self = [super init];
    if (self != nil) {
        _path = [path copy];
        _name = [[path lastPathComponent] copy];
        _isDirectory = isDirectory;
        _kind = OMDExplorerFileKindForPath(path, isDirectory);
        _parent = parent;
    }
    return self;
}

- (void)dealloc
{
    [_path release];
    [_name release];
    [_allChildren release];
    [_visibleChildren release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<OMDExplorerNode %@%@>", _path, (_isDirectory ? @"/" : @"")];
}

- (NSString *)path
{
    return _path;
}

- (NSString *)name
{
    return _name;
}

- (BOOL)isDirectory
{
    return _isDirectory;
}

- (OMDExplorerFileKind)kind
{
    return _kind;
}

- (OMDExplorerNode *)parent
{
    return _parent;
}

- (BOOL)hasLoadedChildren
{
    return _allChildren != nil;
}

// The folder's entries as nodes, reusing previous's node for a name whose
// kind (file or folder) hasn't changed.
- (NSArray *)readChildrenReusing:(NSArray *)previous
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *names = [fileManager contentsOfDirectoryAtPath:_path error:NULL];
    if (names == nil) {
        return [NSArray array];
    }

    NSMutableDictionary *previousByName = [NSMutableDictionary dictionary];
    for (OMDExplorerNode *node in previous) {
        [previousByName setObject:node forKey:[node name]];
    }

    NSMutableArray *children = [NSMutableArray arrayWithCapacity:[names count]];
    for (NSString *name in names) {
        if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
            continue;
        }
        NSString *childPath = [_path stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:childPath isDirectory:&isDirectory]) {
            continue;
        }
        OMDExplorerNode *existing = [previousByName objectForKey:name];
        if (existing != nil && [existing isDirectory] == isDirectory) {
            [children addObject:existing];
        } else {
            OMDExplorerNode *node = [[OMDExplorerNode alloc] initWithPath:childPath
                                                              isDirectory:isDirectory
                                                                   parent:self];
            [children addObject:node];
            [node release];
        }
    }

    [children sortUsingComparator:^NSComparisonResult(id left, id right) {
        BOOL leftIsDirectory = [left isDirectory];
        if (leftIsDirectory != [right isDirectory]) {
            return leftIsDirectory ? NSOrderedAscending : NSOrderedDescending;
        }
        NSComparisonResult result = [[left name] caseInsensitiveCompare:[right name]];
        return (result != NSOrderedSame ? result : [[left name] compare:[right name]]);
    }];
    return children;
}

- (NSArray *)childrenShowingHidden:(BOOL)showHidden
{
    if (!_isDirectory) {
        return [NSArray array];
    }
    if (_allChildren == nil) {
        _allChildren = [[self readChildrenReusing:nil] retain];
        [_visibleChildren release];
        _visibleChildren = nil;
    }
    if (_visibleChildren == nil || _visibleChildrenShowHidden != showHidden) {
        NSArray *visible = _allChildren;
        if (!showHidden) {
            NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:[_allChildren count]];
            for (OMDExplorerNode *node in _allChildren) {
                if (![[node name] hasPrefix:@"."]) {
                    [filtered addObject:node];
                }
            }
            visible = filtered;
        }
        [_visibleChildren release];
        _visibleChildren = [visible copy];
        _visibleChildrenShowHidden = showHidden;
    }
    return _visibleChildren;
}

- (void)reloadChildren
{
    if (!_isDirectory || _allChildren == nil) {
        return;
    }
    NSArray *children = [[self readChildrenReusing:_allChildren] retain];
    [_allChildren release];
    _allChildren = children;
    [_visibleChildren release];
    _visibleChildren = nil;
    for (OMDExplorerNode *node in _allChildren) {
        [node reloadChildren];
    }
}

- (OMDExplorerNode *)descendantForPath:(NSString *)path
{
    if (path == nil || ![path isAbsolutePath]) {
        return nil;
    }
    NSString *target = [path stringByStandardizingPath];
    if ([target isEqualToString:_path]) {
        return self;
    }
    NSString *prefix = ([_path hasSuffix:@"/"] ? _path : [_path stringByAppendingString:@"/"]);
    if (![target hasPrefix:prefix]) {
        return nil;
    }

    OMDExplorerNode *node = self;
    NSArray *components = [[target substringFromIndex:[prefix length]] pathComponents];
    for (NSString *component in components) {
        if ([component length] == 0 || [component isEqualToString:@"/"]) {
            continue;
        }
        OMDExplorerNode *next = nil;
        for (OMDExplorerNode *child in [node childrenShowingHidden:YES]) {
            if ([[child name] isEqualToString:component]) {
                next = child;
                break;
            }
        }
        if (next == nil) {
            return nil;
        }
        node = next;
    }
    return node;
}

@end

BOOL OMDExplorerNameMatchesFilter(NSString *name, NSString *filter)
{
    if ([filter length] == 0) {
        return YES;
    }
    return ([name rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound);
}

NSArray *OMDExplorerFindFiles(NSString *root,
                              NSString *filter,
                              BOOL showHidden,
                              BOOL markdownOnly,
                              NSUInteger visitLimit,
                              NSUInteger matchLimit,
                              BOOL *complete)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray *matches = [NSMutableArray array];
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    BOOL sawEverything = YES;

    while ([pending count] > 0) {
        NSString *folder = [[[pending objectAtIndex:0] retain] autorelease];
        [pending removeObjectAtIndex:0];
        NSArray *names = [[fileManager contentsOfDirectoryAtPath:folder error:NULL]
                          sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
        NSMutableArray *subfolders = [NSMutableArray array];
        for (NSString *name in names) {
            if (visited >= visitLimit || [matches count] >= matchLimit) {
                sawEverything = NO;
                break;
            }
            visited++;
            if ([name isEqualToString:@".git"] || (!showHidden && [name hasPrefix:@"."])) {
                continue;
            }
            NSString *path = [folder stringByAppendingPathComponent:name];
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:NULL];
            BOOL isLink = [[attributes fileType] isEqualToString:NSFileTypeSymbolicLink];
            BOOL isDirectory = NO;
            if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
                continue;
            }
            if (isDirectory) {
                if (!isLink) {
                    [subfolders addObject:path];
                }
                continue;
            }
            if (markdownOnly && OMDExplorerFileKindForPath(path, NO) != OMDExplorerFileKindMarkdown) {
                continue;
            }
            if (OMDExplorerNameMatchesFilter(name, filter)) {
                [matches addObject:path];
            }
        }
        if (!sawEverything) {
            break;
        }
        [pending addObjectsFromArray:subfolders];
    }

    if (complete != NULL) {
        *complete = sawEverything;
    }
    return matches;
}

NSSet *OMDExplorerVisiblePathsForFiles(NSArray *files, NSString *root)
{
    NSMutableSet *paths = [NSMutableSet set];
    NSString *prefix = ([root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"]);
    for (NSString *file in files) {
        if (![file hasPrefix:prefix]) {
            continue;
        }
        NSString *path = file;
        while ([path hasPrefix:prefix] && ![paths containsObject:path]) {
            [paths addObject:path];
            path = [path stringByDeletingLastPathComponent];
        }
    }
    return paths;
}
