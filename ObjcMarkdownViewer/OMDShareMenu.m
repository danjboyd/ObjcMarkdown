// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareMenu.h"
#import "OMDShareExporter.h"

static NSString * const OMDShareLastFormatKey = @"OMDShareLastFormat";
static NSString * const OMDShareLastEmailChoiceKey = @"OMDShareLastEmailChoice";

static BOOL OMDShareIsFormat(NSInteger value)
{
    return value >= OMDShareFormatPDF && value <= OMDShareFormatHTML;
}

void OMDAddShareMenuItems(NSMenu *menu, id target)
{
    OMDShareFormat formats[] = {
        OMDShareFormatPDF, OMDShareFormatWord, OMDShareFormatMarkdown, OMDShareFormatHTML
    };
    // An HTML file is rarely what an email wants: HTML goes in the message.
    OMDShareFormat emailFormats[] = {
        OMDShareFormatPDF, OMDShareFormatWord, OMDShareFormatMarkdown
    };
    NSUInteger index = 0;
    for (index = 0; index < sizeof(formats) / sizeof(formats[0]); index++) {
        NSString *title = [NSString stringWithFormat:@"Share as %@...",
                                                     [OMDShareExporter displayNameForFormat:formats[index]]];
        NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:title
                                                         action:@selector(shareDocument:)
                                                  keyEquivalent:@""];
        [item setTag:formats[index]];
        [item setTarget:target];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    // Email as > PDF, Word Document, Markdown File, In the Message; the
    // last one used is ticked.
    NSMenu *emailMenu = [[[NSMenu alloc] initWithTitle:@"Email as"] autorelease];
    for (index = 0; index < sizeof(emailFormats) / sizeof(emailFormats[0]); index++) {
        NSMenuItem *item = (NSMenuItem *)[emailMenu addItemWithTitle:[OMDShareExporter displayNameForFormat:emailFormats[index]]
                                                              action:@selector(emailDocument:)
                                                       keyEquivalent:@""];
        [item setTag:emailFormats[index]];
        [item setTarget:target];
    }
    [emailMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *inMessage = (NSMenuItem *)[emailMenu addItemWithTitle:@"In the Message"
                                                                action:@selector(emailDocument:)
                                                         keyEquivalent:@""];
    [inMessage setTag:OMDShareEmailInMessageTag];
    [inMessage setTarget:target];
    NSMenuItem *emailItem = (NSMenuItem *)[menu addItemWithTitle:@"Email as" action:NULL keyEquivalent:@""];
    [menu setSubmenu:emailMenu forItem:emailItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [[menu addItemWithTitle:@"Copy Rendered"
                     action:@selector(copyRenderedDocument:)
              keyEquivalent:@""] setTarget:target];
    [[menu addItemWithTitle:@"Copy for Slack"
                     action:@selector(copyDocumentForSlack:)
              keyEquivalent:@""] setTarget:target];
    [[menu addItemWithTitle:@"Show File in Folder"
                     action:@selector(showDocumentInFolder:)
              keyEquivalent:@""] setTarget:target];
}

OMDShareFormat OMDShareLastFormat(void)
{
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:OMDShareLastFormatKey];
    return OMDShareIsFormat(value) ? (OMDShareFormat)value : OMDShareFormatPDF;
}

void OMDShareSetLastFormat(OMDShareFormat format)
{
    [[NSUserDefaults standardUserDefaults] setInteger:format forKey:OMDShareLastFormatKey];
}

NSInteger OMDShareLastEmailChoice(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:OMDShareLastEmailChoiceKey] == nil) {
        return OMDShareFormatPDF;
    }
    NSInteger value = [defaults integerForKey:OMDShareLastEmailChoiceKey];
    if (value == OMDShareEmailInMessageTag || (OMDShareIsFormat(value) && value != OMDShareFormatHTML)) {
        return value;
    }
    return OMDShareFormatPDF;
}

void OMDShareSetLastEmailChoice(NSInteger choice)
{
    [[NSUserDefaults standardUserDefaults] setInteger:choice forKey:OMDShareLastEmailChoiceKey];
}
