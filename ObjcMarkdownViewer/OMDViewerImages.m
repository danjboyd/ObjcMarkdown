// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDViewerImages.h"

NSImage *OMDImageNamed(NSString *resourceName)
{
    if (resourceName == nil || [resourceName length] == 0) {
        return nil;
    }

    NSImage *image = [NSImage imageNamed:resourceName];
    if (image != nil) {
        return image;
    }

    NSString *baseName = [resourceName stringByDeletingPathExtension];
    NSString *extension = [resourceName pathExtension];
    if (extension == nil || [extension length] == 0) {
        extension = @"png";
    }
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:baseName ofType:extension];
    if (resourcePath == nil && [baseName length] > 0) {
        resourcePath = [[NSBundle mainBundle] pathForResource:resourceName ofType:nil];
    }
    if (resourcePath != nil) {
        NSImage *fileImage = [[[NSImage alloc] initWithContentsOfFile:resourcePath] autorelease];
        if (fileImage != nil) {
            return fileImage;
        }
    }
    return nil;
}

#if !defined(GNUSTEP)
// The SF Symbol macOS draws for each of the app's symbolic icons.
static NSString *OMDSystemSymbolNameForIcon(NSString *name)
{
    static NSDictionary *symbols = nil;
    if (symbols == nil) {
        symbols = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"square.and.arrow.up", @"omd-document-export-symbolic",
            @"square.and.arrow.down", @"omd-document-import-symbolic",
            @"folder", @"omd-document-open-symbolic",
            @"printer", @"omd-document-print-symbolic",
            @"square.and.arrow.down.on.square", @"omd-document-save-symbolic",
            @"doc.on.doc", @"omd-edit-copy-symbolic",
            @"folder", @"omd-folder-symbolic",
            @"curlybraces", @"omd-format-code-block-symbolic",
            @"chevron.left.forwardslash.chevron.right", @"omd-format-code-symbolic",
            @"text.quote", @"omd-format-quote-symbolic",
            @"bold", @"omd-format-text-bold-symbolic",
            @"italic", @"omd-format-text-italic-symbolic",
            @"strikethrough", @"omd-format-text-strikethrough-symbolic",
            @"photo", @"omd-insert-image-symbolic",
            @"link", @"omd-insert-link-symbolic",
            @"minus", @"omd-insert-rule-symbolic",
            @"tablecells", @"omd-insert-table-symbolic",
            @"checkmark", @"omd-object-select-symbolic",
            @"chevron.down", @"omd-pan-down-symbolic",
            @"gearshape", @"omd-preferences-symbolic",
            @"sidebar.left", @"omd-sidebar-show-symbolic",
            @"doc", @"omd-text-x-generic-symbolic",
            @"doc.text", @"omd-text-x-markdown-symbolic",
            @"list.bullet", @"omd-view-list-bullet-symbolic",
            @"list.number", @"omd-view-list-ordered-symbolic",
            @"checklist", @"omd-view-list-task-symbolic",
            nil];
    }
    return [symbols objectForKey:name];
}
#endif

NSImage *OMDSymbolicImageNamedForCommand(NSString *name, NSString *commandName)
{
    NSImage *image = OMDSymbolicImageNamed(name);
#if !defined(GNUSTEP)
    // A copy: the shared image stands for other commands elsewhere.
    if (image != nil && [commandName length] > 0) {
        image = [[image copy] autorelease];
        [image setAccessibilityDescription:commandName];
    }
#else
    (void)commandName;
#endif
    return image;
}

NSString *OMDShortcutText(NSString *text)
{
#if !defined(GNUSTEP)
    return [text stringByReplacingOccurrencesOfString:@"Ctrl+" withString:@"\u2318"];
#else
    return text;
#endif
}

NSImage *OMDSymbolicImageNamed(NSString *name)
{
#if !defined(GNUSTEP)
    // macOS's own symbols where it has them (checklist needs macOS 12).
    if (@available(macOS 11.0, *)) {
        NSString *symbolName = OMDSystemSymbolNameForIcon(name);
        NSImage *symbol = symbolName != nil ? [NSImage imageWithSystemSymbolName:symbolName
                                                        accessibilityDescription:nil] : nil;
        if (symbol != nil) {
            return symbol;
        }
    }
    // Otherwise the app's own icon as a template, which AppKit tints for
    // light and dark, as it does symbols.
    NSImage *image = [NSImage imageNamed:name];
    [image setTemplate:YES];
    return image;
#else
    NSImage *image = [NSImage imageNamed:name];
    // Drawn from its bitmap every time. On Windows the cached copy GNUstep
    // keeps of a shared image can stay blank (here every formatting-bar
    // icon, under any theme); see the GNUstep notes in AGENTS.md.
    [image setCacheMode:NSImageCacheNever];
    return image;
#endif
}
