// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDPanelSelection.h"

static void OMDAppendURLPaths(NSMutableArray *paths, id urlsValue)
{
    if (paths == nil || ![urlsValue isKindOfClass:[NSArray class]]) {
        return;
    }

    for (id value in (NSArray *)urlsValue) {
        if (![value isKindOfClass:[NSURL class]]) {
            continue;
        }
        NSURL *url = (NSURL *)value;
        if (![url isFileURL]) {
            continue;
        }
        NSString *path = [url path];
        if (path != nil && [path length] > 0) {
            [paths addObject:path];
        }
    }
}

static void OMDAppendStringPaths(NSMutableArray *paths, id filenamesValue)
{
    if (paths == nil || ![filenamesValue isKindOfClass:[NSArray class]]) {
        return;
    }

    for (id value in (NSArray *)filenamesValue) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *path = (NSString *)value;
        if ([path length] > 0) {
            [paths addObject:path];
        }
    }
}

NSArray *OMDSelectedPathsFromOpenPanel(NSOpenPanel *panel)
{
    if (panel == nil) {
        return [NSArray array];
    }

    NSMutableArray *paths = [NSMutableArray array];
    if ([panel respondsToSelector:@selector(URLs)]) {
        OMDAppendURLPaths(paths, [panel URLs]);
    }
    if ([paths count] == 0 && [panel respondsToSelector:@selector(filenames)]) {
        OMDAppendStringPaths(paths, [panel filenames]);
    }
    if ([paths count] == 0 && [panel respondsToSelector:@selector(URL)]) {
        NSURL *url = [panel URL];
        if ([url isFileURL] && [[url path] length] > 0) {
            [paths addObject:[url path]];
        }
    }
    if ([paths count] == 0 && [panel respondsToSelector:@selector(filename)]) {
        NSString *path = [panel filename];
        if (path != nil && [path length] > 0) {
            [paths addObject:path];
        }
    }

    return paths;
}

NSString *OMDSelectedPathFromSavePanel(NSSavePanel *panel)
{
    if (panel == nil) {
        return nil;
    }

    if ([panel respondsToSelector:@selector(URL)]) {
        NSURL *url = [panel URL];
        if ([url isFileURL] && [[url path] length] > 0) {
            return [url path];
        }
    }

    if ([panel respondsToSelector:@selector(filename)]) {
        NSString *path = [panel filename];
        if (path != nil && [path length] > 0) {
            return path;
        }
    }

    return nil;
}
