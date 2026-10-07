// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDControlSupport.h"
#import "OMDLayoutMetrics.h"

CGFloat OMDControlWidthForTitle(NSString *title,
                                       NSFont *font,
                                       CGFloat minWidth,
                                       CGFloat horizontalPadding)
{
    if (minWidth < 1.0) {
        minWidth = 1.0;
    }
    if (horizontalPadding < 0.0) {
        horizontalPadding = 0.0;
    }
    if (title == nil || [title length] == 0) {
        return ceil(minWidth);
    }
    if (font == nil) {
<<<<<<< Updated upstream
        font = OMDChromeFont();
=======
        font = [NSFont controlContentFontOfSize:0.0];
>>>>>>> Stashed changes
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName,
                                nil];
    CGFloat width = ceil([title sizeWithAttributes:attributes].width + (horizontalPadding * 2.0));
    if (width < minWidth) {
        width = minWidth;
    }
    return width;
}

void OMDClearSegmentedControlSelection(NSSegmentedControl *control)
{
    if (control == nil) {
        return;
    }
    NSInteger segmentCount = [control segmentCount];
    NSInteger segmentIndex = 0;
    for (; segmentIndex < segmentCount; segmentIndex++) {
        [control setSelected:NO forSegment:segmentIndex];
    }
}
