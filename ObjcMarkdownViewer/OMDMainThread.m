// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDMainThread.h"

@interface OMDMainThreadBlock : NSObject
{
    void (^_block)(void);
}
- (instancetype)initWithBlock:(void (^)(void))block;
- (void)run;
@end

@implementation OMDMainThreadBlock

- (instancetype)initWithBlock:(void (^)(void))block
{
    self = [super init];
    if (self != nil) {
        _block = [block copy];
    }
    return self;
}

- (void)dealloc
{
    [_block release];
    [super dealloc];
}

- (void)run
{
    _block();
}

@end

void OMDPerformOnMainThread(void (^block)(void))
{
    if (block == nil) {
        return;
    }
    OMDMainThreadBlock *runner = [[OMDMainThreadBlock alloc] initWithBlock:block];
    [runner performSelectorOnMainThread:@selector(run) withObject:nil waitUntilDone:NO];
    [runner release];
}
