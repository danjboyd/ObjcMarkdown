// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRelaunchReopen.h"

NSString * const OMDRelaunchReopenDefaultsKey = @"ObjcMarkdownRelaunchReopen";

static NSString * const OMDRelaunchReopenVersionKey = @"version";
static NSString * const OMDRelaunchReopenPathsKey = @"paths";
static NSString * const OMDRelaunchReopenSelectedKey = @"selected";

NSDictionary *OMDRelaunchReopenRecordMake(NSString *version, NSArray *paths, NSString *selectedPath)
{
    if ([version length] == 0 || [paths count] == 0) {
        return nil;
    }
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    [record setObject:version forKey:OMDRelaunchReopenVersionKey];
    [record setObject:[NSArray arrayWithArray:paths] forKey:OMDRelaunchReopenPathsKey];
    if ([selectedPath length] > 0) {
        [record setObject:selectedPath forKey:OMDRelaunchReopenSelectedKey];
    }
    return record;
}

NSArray *OMDRelaunchReopenPathsForLaunch(NSDictionary *record,
                                         NSString *currentVersion,
                                         BOOL (^fileExists)(NSString *path))
{
    if (![record isKindOfClass:[NSDictionary class]]) {
        return [NSArray array];
    }
    id version = [record objectForKey:OMDRelaunchReopenVersionKey];
    id paths = [record objectForKey:OMDRelaunchReopenPathsKey];
    if (![version isKindOfClass:[NSString class]] || [version length] == 0 ||
        [version isEqualToString:currentVersion] || ![paths isKindOfClass:[NSArray class]]) {
        return [NSArray array];
    }
    NSMutableArray *result = [NSMutableArray array];
    for (id path in paths) {
        if (![path isKindOfClass:[NSString class]] || [path length] == 0 || [result containsObject:path]) {
            continue;
        }
        if (fileExists == nil || fileExists(path)) {
            [result addObject:path];
        }
    }
    id selected = [record objectForKey:OMDRelaunchReopenSelectedKey];
    if ([selected isKindOfClass:[NSString class]] && [result containsObject:selected] &&
        ![[result lastObject] isEqualToString:selected]) {
        [result addObject:selected];
    }
    return result;
}
