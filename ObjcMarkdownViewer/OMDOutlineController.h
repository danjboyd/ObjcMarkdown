// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDOutlineController;

@protocol OMDOutlineControllerDelegate <NSObject>
// heading is one of the renderer's -headings dictionaries.
- (void)outlineController:(OMDOutlineController *)controller didChooseHeading:(NSDictionary *)heading;
@end

// The document outline panel: a list of the rendered document's headings,
// indented by level, with the section being read highlighted.
@interface OMDOutlineController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithFrame:(NSRect)frame;

@property (nonatomic, readonly) NSView *view;
@property (nonatomic, assign) id<OMDOutlineControllerDelegate> delegate;
// The renderer's -headings for the shown document.
@property (nonatomic, copy) NSArray *headings;
// The highlighted heading, or -1; setting it doesn't notify the delegate.
@property (nonatomic, assign) NSInteger currentHeadingIndex;

// Index of the heading whose section holds a location in the rendered string:
// the last heading starting at or before it, or -1 before the first heading.
+ (NSInteger)headingIndexForRenderedLocation:(NSUInteger)location inHeadings:(NSArray *)headings;
// The same, for a 1-based source line.
+ (NSInteger)headingIndexForSourceLine:(NSUInteger)line inHeadings:(NSArray *)headings;

@end
