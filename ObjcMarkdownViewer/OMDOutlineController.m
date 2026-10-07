// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDOutlineController.h"
#import "OMDLayoutMetrics.h"
#import "OMMarkdownRenderer.h"

// The header and rows fit the theme's text (OMDChromeFont).
static CGFloat OMDOutlineHeaderHeight(void)
{
    return MAX(30.0, OMDChromeLineHeight(OMDChromeBoldFont()) + 12.0);
}
static const CGFloat OMDOutlineIndentPerLevel = 12.0;

@interface OMDOutlineController ()
{
    NSView *_view;
    NSTextField *_titleLabel;
    NSTextField *_emptyLabel;
    NSScrollView *_scrollView;
    NSTableView *_tableView;
    NSArray *_headings;
    NSInteger _currentHeadingIndex;
    NSInteger _minimumLevel;
}
@end

@implementation OMDOutlineController

@synthesize delegate = _delegate;

static NSTextField *OMDOutlineLabel(NSRect frame, NSFont *font, NSColor *color)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setDrawsBackground:NO];
    [label setFont:font];
    [label setTextColor:color];
    return label;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _currentHeadingIndex = -1;
    _minimumLevel = 1;
    _headings = [[NSArray alloc] init];

    _view = [[NSView alloc] initWithFrame:frame];
    [_view setAutoresizingMask:(NSViewMinXMargin | NSViewHeightSizable)];

    NSRect bounds = [_view bounds];
    CGFloat headerHeight = OMDOutlineHeaderHeight();
    CGFloat labelHeight = OMDChromeLineHeight(OMDChromeBoldFont());
    _titleLabel = OMDOutlineLabel(NSMakeRect(12.0, NSHeight(bounds) - headerHeight + 6.0,
                                             NSWidth(bounds) - 24.0, labelHeight),
                                  OMDChromeBoldFont(),
                                  [NSColor controlTextColor]);
    [_titleLabel setStringValue:@"Outline"];
    [_titleLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_view addSubview:_titleLabel];

    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(bounds),
                                                                 NSHeight(bounds) - headerHeight)];
    [_scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:NO];
    [_scrollView setBorderType:NSNoBorder];

    _tableView = [[NSTableView alloc] initWithFrame:[[_scrollView contentView] bounds]];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"heading"] autorelease];
    [column setWidth:NSWidth(bounds)];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setEditable:NO];
    [[column dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [_tableView addTableColumn:column];
    [_tableView setHeaderView:nil];
    [_tableView setCornerView:nil];
    [_tableView setRowHeight:MAX(22.0, OMDChromeLineHeight(OMDChromeBoldFont()) + 4.0)];
    [_tableView setIntercellSpacing:NSMakeSize(0.0, 2.0)];
    [_tableView setAllowsEmptySelection:YES];
    [_tableView setAllowsMultipleSelection:NO];
    [_tableView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setTarget:self];
    [_tableView setAction:@selector(rowClicked:)];
    [_scrollView setDocumentView:_tableView];
    [_view addSubview:_scrollView];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1.0, NSHeight(bounds))] autorelease];
    [separator setBoxType:NSBoxSeparator];
    [separator setAutoresizingMask:(NSViewMaxXMargin | NSViewHeightSizable)];
    [_view addSubview:separator];

    CGFloat noteHeight = OMDChromeLineHeight(OMDChromeSmallFont());
    _emptyLabel = OMDOutlineLabel(NSMakeRect(12.0, NSHeight(bounds) - headerHeight - noteHeight - 6.0,
                                             NSWidth(bounds) - 24.0, noteHeight),
                                  OMDChromeSmallFont(),
                                  [NSColor secondaryLabelColor]);
    [_emptyLabel setStringValue:@"No headings"];
    [_emptyLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [_view addSubview:_emptyLabel];
    return self;
}

- (void)dealloc
{
    [_tableView setDataSource:nil];
    [_tableView setDelegate:nil];
    [_titleLabel release];
    [_emptyLabel release];
    [_tableView release];
    [_scrollView release];
    [_view release];
    [_headings release];
    [super dealloc];
}

- (NSView *)view
{
    return _view;
}

- (NSArray *)headings
{
    return _headings;
}

- (void)setHeadings:(NSArray *)headings
{
    NSArray *copied = [(headings != nil ? headings : [NSArray array]) copy];
    [_headings release];
    _headings = copied;
    _minimumLevel = 6;
    for (NSDictionary *heading in _headings) {
        NSInteger level = [[heading objectForKey:OMMarkdownRendererHeadingLevelKey] integerValue];
        if (level >= 1 && level < _minimumLevel) {
            _minimumLevel = level;
        }
    }
    [_emptyLabel setHidden:([_headings count] > 0)];
    [_tableView reloadData];
    if (_currentHeadingIndex >= (NSInteger)[_headings count]) {
        _currentHeadingIndex = -1;
    }
    [self setCurrentHeadingIndex:_currentHeadingIndex];
}

- (NSInteger)currentHeadingIndex
{
    return _currentHeadingIndex;
}

- (void)setCurrentHeadingIndex:(NSInteger)index
{
    if (index < -1 || index >= (NSInteger)[_headings count]) {
        index = -1;
    }
    _currentHeadingIndex = index;
    if (index < 0) {
        [_tableView deselectAll:nil];
        return;
    }
    if ([_tableView selectedRow] != index) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] byExtendingSelection:NO];
    }
    [_tableView scrollRowToVisible:index];
}

- (void)rowClicked:(id)sender
{
    NSInteger row = [_tableView clickedRow];
    if (row < 0) {
        row = [_tableView selectedRow];
    }
    if (row < 0 || row >= (NSInteger)[_headings count]) {
        return;
    }
    _currentHeadingIndex = row;
    [_delegate outlineController:self didChooseHeading:[_headings objectAtIndex:(NSUInteger)row]];
}

+ (NSInteger)headingIndexForRenderedLocation:(NSUInteger)location inHeadings:(NSArray *)headings
{
    NSInteger found = -1;
    NSInteger index = 0;
    for (NSDictionary *heading in headings) {
        NSRange range = [[heading objectForKey:OMMarkdownRendererHeadingRangeKey] rangeValue];
        if (range.location > location) {
            break;
        }
        found = index;
        index += 1;
    }
    return found;
}

+ (NSInteger)headingIndexForSourceLine:(NSUInteger)line inHeadings:(NSArray *)headings
{
    NSInteger found = -1;
    NSInteger index = 0;
    for (NSDictionary *heading in headings) {
        if ([[heading objectForKey:OMMarkdownRendererHeadingSourceLineKey] unsignedIntegerValue] > line) {
            break;
        }
        found = index;
        index += 1;
    }
    return found;
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[_headings count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)[_headings count]) {
        return @"";
    }
    NSDictionary *heading = [_headings objectAtIndex:(NSUInteger)row];
    NSInteger level = [[heading objectForKey:OMMarkdownRendererHeadingLevelKey] integerValue];
    NSString *title = [heading objectForKey:OMMarkdownRendererHeadingTitleKey];
    if ([title length] == 0) {
        title = @"Untitled";
    }
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    CGFloat indent = 12.0 + OMDOutlineIndentPerLevel * (CGFloat)MAX(0, level - _minimumLevel);
    [style setFirstLineHeadIndent:indent];
    [style setHeadIndent:indent];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    NSFont *font = (level == _minimumLevel) ? OMDChromeBoldFont() : OMDChromeFont();
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName,
                                style, NSParagraphStyleAttributeName,
                                nil];
    return [[[NSAttributedString alloc] initWithString:title attributes:attributes] autorelease];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return NO;
}

@end
