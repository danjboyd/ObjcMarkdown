// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Mermaid diagrams: drawing supported types, diagnostics for the rest.

#import "OMMarkdownRendererInternal.h"

static NSColor *OMMermaidDiagnosticColorForTheme(OMTheme *theme)
{
    NSColor *base = theme != nil ? [theme baseTextColor] : nil;
    if (base == nil) {
        return [NSColor grayColor];
    }
    NSColor *muted = [base colorWithAlphaComponent:0.7];
    return muted != nil ? muted : base;
}

// Diagram line numbers are relative to the fenced block, so shift them onto the
// enclosing document, which is the line the reader can actually navigate to.
static NSString *OMMermaidDiagnosticMessageForError(NSError *error, cmark_node *codeBlockNode)
{
    NSString *description = [[error userInfo] objectForKey:NSLocalizedDescriptionKey];
    if (description == nil || [description length] == 0) {
        description = @"Diagram could not be parsed.";
    }

    NSNumber *lineNumber = [[error userInfo] objectForKey:OMMermaidERDiagramErrorLineNumberKey];
    if (lineNumber == nil || [lineNumber unsignedIntegerValue] == 0) {
        return [NSString stringWithFormat:@"mermaid erDiagram: %@", description];
    }

    NSUInteger reportedLine = [lineNumber unsignedIntegerValue];
    NSUInteger fenceLine = 0;
    if (OMNodeLineBounds(codeBlockNode, &fenceLine, NULL)) {
        reportedLine += fenceLine;
    }
    return [NSString stringWithFormat:@"mermaid erDiagram, line %lu: %@",
            (unsigned long)reportedLine,
            description];
}

// Colors follow the pipe-table palette so a diagram sits in the same visual
// family as a table, in both light and dark themes.
static OMMermaidERDrawingStyle *OMMermaidStyleForTheme(OMTheme *theme,
                                                       NSDictionary *attributes,
                                                       CGFloat scale)
{
    NSFont *baseFont = [attributes objectForKey:NSFontAttributeName];
    CGFloat baseSize = baseFont != nil
        ? [baseFont pointSize]
        : ((theme.baseFont != nil ? [theme.baseFont pointSize] : 14.0) * scale);
    CGFloat attributeSize = MAX(baseSize * 0.84, 8.0 * scale);
    CGFloat titleSize = MAX(baseSize * 0.92, 9.0 * scale);
    CGFloat labelSize = MAX(baseSize * 0.76, 7.5 * scale);

    NSFont *attributeFont = baseFont != nil
        ? [NSFont fontWithName:[baseFont fontName] size:attributeSize]
        : [NSFont systemFontOfSize:attributeSize];
    NSFont *titleFont = baseFont != nil
        ? [NSFont fontWithName:[baseFont fontName] size:titleSize]
        : [NSFont systemFontOfSize:titleSize];
    NSFont *boldTitleFont = OMFontWithTraits(titleFont, NSBoldFontMask);
    NSFont *labelFont = baseFont != nil
        ? [NSFont fontWithName:[baseFont fontName] size:labelSize]
        : [NSFont systemFontOfSize:labelSize];

    NSColor *textColor = [attributes objectForKey:NSForegroundColorAttributeName];
    if (textColor == nil) {
        textColor = theme.baseTextColor != nil ? theme.baseTextColor : [NSColor blackColor];
    }
    NSColor *mutedColor = [textColor colorWithAlphaComponent:0.68];
    if (mutedColor == nil) {
        mutedColor = textColor;
    }
    NSColor *edgeColor = [textColor colorWithAlphaComponent:0.55];
    if (edgeColor == nil) {
        edgeColor = textColor;
    }

    OMMermaidERDrawingStyle *style = [[[OMMermaidERDrawingStyle alloc] init] autorelease];
    [style setTitleFont:(boldTitleFont != nil ? boldTitleFont : titleFont)];
    [style setAttributeFont:attributeFont];
    [style setLabelFont:labelFont];
    [style setBorderColor:OMPipeTableBorderColorForTheme(theme)];
    [style setTitleBackgroundColor:OMPipeTableHeaderBackgroundColorForTheme(theme)];
    [style setBodyBackgroundColor:OMPipeTableBodyBackgroundColorForTheme(theme)];
    [style setTextColor:textColor];
    [style setKeyColor:(theme.linkColor != nil ? theme.linkColor : mutedColor)];
    [style setCommentColor:mutedColor];
    [style setEdgeColor:edgeColor];
    [style setBorderWidth:MAX(1.0, scale)];
    return style;
}

// Draws a parsed erDiagram as a block attachment. Returns NO when the diagram
// cannot be laid out, which leaves the caller on the code-block path.
// diagram is an OMMermaidERDiagram or an OMMermaidFlowchart.
static BOOL OMAppendMermaidDiagram(id diagram,
                                   NSString *source,
                                   OMTheme *theme,
                                   NSMutableAttributedString *output,
                                   NSMutableDictionary *attributes,
                                   NSUInteger quoteLevel,
                                   CGFloat scale,
                                   const OMRenderContext *renderContext)
{
    OMMermaidERDrawingStyle *style = OMMermaidStyleForTheme(theme, attributes, scale);
    CGFloat indent = (CGFloat)(quoteLevel * 20.0 * scale) + OMListContentIndent(renderContext, scale) + 20.0 * scale;
    CGFloat layoutWidth = renderContext != NULL ? renderContext->layoutWidth : 0.0;
    CGFloat maximumWidth = 0.0;
    if (layoutWidth > 0.0) {
        maximumWidth = layoutWidth - indent - (16.0 * scale);
        if (maximumWidth < 120.0 * scale) {
            maximumWidth = 120.0 * scale;
        }
    }

    NSMutableDictionary *diagramAttributes = [attributes mutableCopy];
    [diagramAttributes removeObjectForKey:NSBackgroundColorAttributeName];
    NSMutableParagraphStyle *paragraphStyle = OMParagraphStyleWithIndent(indent,
                                                                        indent,
                                                                        14.0 * scale,
                                                                        0.0,
                                                                        1.0,
                                                                        0.0);
    [paragraphStyle setParagraphSpacingBefore:10.0 * scale];
    // Centred like display math, as GitHub shows diagrams.
    [paragraphStyle setAlignment:NSCenterTextAlignment];
    [diagramAttributes setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];

    NSAttributedString *attachment = [diagram isKindOfClass:[OMMermaidFlowchart class]]
        ? OMMermaidFlowchartAttachmentAttributedString(diagram, style, maximumWidth, diagramAttributes)
        : OMMermaidERAttachmentAttributedString(diagram, style, maximumWidth, diagramAttributes);
    if (attachment == nil) {
        [diagramAttributes release];
        return NO;
    }

    NSUInteger diagramStart = [output length];
    OMAppendAttributedSegment(output, attachment);
    NSString *diagramSource = (source != nil ? source : @"");
    OMTagAppendedObject(output,
                        diagramStart,
                        OMRenderedObjectKindDiagram,
                        diagramSource,
                        [NSString stringWithFormat:@"```mermaid\n%@%@```",
                         diagramSource,
                         ([diagramSource hasSuffix:@"\n"] ? @"" : @"\n")]);
    if (renderContext != NULL && renderContext->diagramBlocks != nil) {
        NSRange diagramRange = NSMakeRange(diagramStart, [output length] - diagramStart);
        [renderContext->diagramBlocks addObject:
            [NSDictionary dictionaryWithObjectsAndKeys:
                [NSValue valueWithRange:diagramRange], OMMarkdownRendererDiagramRangeKey,
                (source != nil ? source : @""), OMMarkdownRendererDiagramSourceKey,
                nil]];
    }
    OMAppendString(output, @"\n", diagramAttributes);
    // A blank line after the diagram, as after code blocks and paragraphs.
    OMAppendString(output, @"\n", attributes);
    [diagramAttributes release];
    return YES;
}

// Mermaid fences are recognized here. An erDiagram that parses and fits is drawn
// as an attachment; everything else -- other mermaid diagram types, malformed
// source, and diagrams too large to draw -- falls back to the code block, with a
// diagnostic line when the block claimed to be an erDiagram.
BOOL OMTryRenderMermaidDiagram(cmark_node *node,
                               NSString *code,
                               OMTheme *theme,
                               NSMutableAttributedString *output,
                               NSMutableDictionary *attributes,
                               NSUInteger quoteLevel,
                               CGFloat scale,
                               const OMRenderContext *renderContext,
                               NSString **diagnosticOut)
{
    if (diagnosticOut != NULL) {
        *diagnosticOut = nil;
    }

    NSString *fenceToken = OMPrimaryFenceToken(node);
    if (fenceToken == nil || ![fenceToken isEqualToString:@"mermaid"]) {
        return NO;
    }
    if (!OMNativeDiagramRenderingEnabled(renderContext)) {
        return NO;
    }
    if ([OMMermaidFlowchart sourceDeclaresFlowchart:code]) {
        NSError *flowError = nil;
        OMMermaidFlowchart *flowchart = [OMMermaidFlowchart flowchartWithSource:code error:&flowError];
        if (flowchart != nil &&
            OMAppendMermaidDiagram(flowchart, code, theme, output, attributes, quoteLevel, scale, renderContext)) {
            return YES;
        }
        if (diagnosticOut != NULL) {
            NSString *reason = [[flowError userInfo] objectForKey:NSLocalizedDescriptionKey];
            NSNumber *line = [[flowError userInfo] objectForKey:OMMermaidFlowchartErrorLineNumberKey];
            if (line != nil) {
                // Lines count from the fence, as for erDiagram messages.
                int fenceLine = cmark_node_get_start_line(node);
                reason = [NSString stringWithFormat:@"line %ld: %@",
                          (long)([line integerValue] + (fenceLine > 0 ? fenceLine : 0)), reason];
            }
            *diagnosticOut = [NSString stringWithFormat:@"mermaid flowchart: %@",
                              reason != nil ? reason : @"could not be drawn."];
        }
        return NO;
    }
    if (![OMMermaidERDiagram sourceDeclaresERDiagram:code]) {
        // Say why the source shows instead of a drawing.
        NSString *type = OMMermaidDeclaredDiagramType(code);
        if (diagnosticOut != NULL && [type length] > 0) {
            *diagnosticOut = [NSString stringWithFormat:@"mermaid %@: this diagram type isn't drawn yet, so its source is shown.", type];
        }
        return NO;
    }

    NSError *error = nil;
    OMMermaidERDiagram *diagram = [OMMermaidERDiagram diagramWithSource:code error:&error];
    if (diagram == nil) {
        if (diagnosticOut != NULL) {
            *diagnosticOut = OMMermaidDiagnosticMessageForError(error, node);
        }
        return NO;
    }

    if (OMAppendMermaidDiagram(diagram, code, theme, output, attributes, quoteLevel, scale, renderContext)) {
        return YES;
    }

    if (diagnosticOut != NULL) {
        *diagnosticOut = [NSString stringWithFormat:
            @"mermaid erDiagram: too large to draw (%lu entities, %lu relationships).",
            (unsigned long)[[diagram entities] count],
            (unsigned long)[[diagram relationships] count]];
    }
    return NO;
}

void OMAppendMermaidDiagnostic(NSString *diagnostic,
                               OMTheme *theme,
                               NSMutableAttributedString *output,
                               NSDictionary *blockAttributes,
                               CGFloat indent,
                               CGFloat codeFontSize,
                               CGFloat scale)
{
    if (diagnostic == nil || [diagnostic length] == 0) {
        return;
    }

    NSMutableDictionary *diagnosticAttrs = [blockAttributes mutableCopy];
    NSFont *blockFont = [diagnosticAttrs objectForKey:NSFontAttributeName];
    CGFloat diagnosticSize = codeFontSize * 0.92;
    NSFont *sizedFont = blockFont != nil ? [NSFont fontWithName:[blockFont fontName] size:diagnosticSize] : nil;
    if (sizedFont == nil) {
        sizedFont = blockFont;
    }
    NSFont *italicFont = OMFontWithTraits(sizedFont, NSItalicFontMask);
    if (italicFont != nil) {
        [diagnosticAttrs setObject:italicFont forKey:NSFontAttributeName];
    } else if (sizedFont != nil) {
        [diagnosticAttrs setObject:sizedFont forKey:NSFontAttributeName];
    }
    [diagnosticAttrs setObject:OMMermaidDiagnosticColorForTheme(theme)
                        forKey:NSForegroundColorAttributeName];
    [diagnosticAttrs removeObjectForKey:NSBackgroundColorAttributeName];

    NSMutableParagraphStyle *style = OMParagraphStyleWithIndent(indent,
                                                                indent,
                                                                8.0 * scale,
                                                                0.0,
                                                                1.3,
                                                                diagnosticSize);
    [style setParagraphSpacingBefore:4.0 * scale];
    // Wrap at the code box's right edge, as the code above does.
    [style setTailIndent:-20.0 * scale];
    [diagnosticAttrs setObject:style forKey:NSParagraphStyleAttributeName];

    OMAppendString(output, diagnostic, diagnosticAttrs);
    OMAppendString(output, @"\n", diagnosticAttrs);
    [diagnosticAttrs release];
}
