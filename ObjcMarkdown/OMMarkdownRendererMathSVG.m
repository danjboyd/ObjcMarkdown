// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

// Typeset math without an SVG reader: dvisvgm --no-fonts writes glyphs as
// filled paths (svg, defs, path, g, use, rect; M L H V C S Q T Z). GNUstep
// reads SVG only when libs-gui is built with ImageMagick, which the Linux
// packages aren't (#246), so this draws that subset itself.

#import "OMMarkdownRendererInternal.h"

// One vector image: the paths in SVG user units, filled in one colour.
@interface OMMathSVGImageRep : NSImageRep
{
    NSArray *_paths;     // NSBezierPath, in SVG user units (y down)
    NSRect _viewBox;
    NSColor *_ink;
}
- (instancetype)initWithPaths:(NSArray *)paths viewBox:(NSRect)viewBox size:(NSSize)size ink:(NSColor *)ink;
@end

@implementation OMMathSVGImageRep

- (instancetype)initWithPaths:(NSArray *)paths viewBox:(NSRect)viewBox size:(NSSize)size ink:(NSColor *)ink
{
    self = [super init];
    if (self != nil) {
        _paths = [paths copy];
        _viewBox = viewBox;
        _ink = [ink retain];
        [self setSize:size];
        [self setPixelsWide:NSImageRepMatchesDevice];
        [self setPixelsHigh:NSImageRepMatchesDevice];
        [self setAlpha:YES];
        [self setOpaque:NO];
    }
    return self;
}

- (void)dealloc
{
    [_paths release];
    [_ink release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    OMMathSVGImageRep *copy = [super copyWithZone:zone];
    copy->_paths = [_paths retain];
    copy->_ink = [_ink retain];
    return copy;
}

- (BOOL)draw
{
    NSSize size = [self size];
    if (NSWidth(_viewBox) <= 0.0 || NSHeight(_viewBox) <= 0.0) {
        return NO;
    }
    [NSGraphicsContext saveGraphicsState];
    // The view box onto (0, 0, size), with SVG's y axis turned up.
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:0.0 yBy:size.height];
    [transform scaleXBy:size.width / NSWidth(_viewBox) yBy:-size.height / NSHeight(_viewBox)];
    [transform translateXBy:-NSMinX(_viewBox) yBy:-NSMinY(_viewBox)];
    [transform concat];
    [(_ink != nil ? _ink : [NSColor blackColor]) set];
    for (NSBezierPath *path in _paths) {
        [path fill];
    }
    [NSGraphicsContext restoreGraphicsState];
    return YES;
}

@end

// SVG path data, as dvisvgm writes it ("M6.84-3.25C6.99-3.25 7.18 ...").
typedef struct {
    const char *cursor;
    const char *end;
} OMSVGScanner;

static void OMSVGSkipSeparators(OMSVGScanner *scanner)
{
    while (scanner->cursor < scanner->end &&
           (*scanner->cursor == ' ' || *scanner->cursor == ',' || *scanner->cursor == '\t' ||
            *scanner->cursor == '\n' || *scanner->cursor == '\r')) {
        scanner->cursor++;
    }
}

static BOOL OMSVGScanNumber(OMSVGScanner *scanner, CGFloat *value)
{
    OMSVGSkipSeparators(scanner);
    const char *start = scanner->cursor;
    const char *p = start;
    if (p < scanner->end && (*p == '-' || *p == '+')) {
        p++;
    }
    BOOL digits = NO;
    BOOL dot = NO;
    while (p < scanner->end && ((*p >= '0' && *p <= '9') || (*p == '.' && !dot))) {
        if (*p == '.') {
            dot = YES;
        } else {
            digits = YES;
        }
        p++;
    }
    if (!digits) {
        return NO;
    }
    if (p < scanner->end && (*p == 'e' || *p == 'E')) {
        const char *q = p + 1;
        if (q < scanner->end && (*q == '-' || *q == '+')) {
            q++;
        }
        if (q < scanner->end && *q >= '0' && *q <= '9') {
            p = q;
            while (p < scanner->end && *p >= '0' && *p <= '9') {
                p++;
            }
        }
    }
    char buffer[64];
    size_t length = (size_t)(p - start);
    if (length >= sizeof(buffer)) {
        return NO;
    }
    memcpy(buffer, start, length);
    buffer[length] = '\0';
    *value = (CGFloat)strtod(buffer, NULL);
    scanner->cursor = p;
    return YES;
}

static BOOL OMSVGScanNumbers(OMSVGScanner *scanner, CGFloat *values, NSUInteger count)
{
    NSUInteger i = 0;
    for (i = 0; i < count; i++) {
        if (!OMSVGScanNumber(scanner, &values[i])) {
            return NO;
        }
    }
    return YES;
}

NSBezierPath *OMMathSVGPathFromData(NSString *data)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    const char *bytes = [data UTF8String];
    if (bytes == NULL) {
        return path;
    }
    OMSVGScanner scanner = { bytes, bytes + strlen(bytes) };
    char command = 0;
    NSPoint current = NSZeroPoint;
    NSPoint start = NSZeroPoint;
    NSPoint lastControl = NSZeroPoint;  // for S and T
    char lastCommand = 0;
    while (YES) {
        OMSVGSkipSeparators(&scanner);
        if (scanner.cursor >= scanner.end) {
            break;
        }
        char c = *scanner.cursor;
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
            command = c;
            scanner.cursor++;
        } else if (command == 0) {
            break;
        }
        BOOL relative = (command >= 'a' && command <= 'z');
        char upper = (char)(relative ? command - 32 : command);
        CGFloat v[6];
        NSPoint base = relative ? current : NSZeroPoint;
        switch (upper) {
        case 'Z':
            [path closePath];
            current = start;
            lastCommand = 'Z';
            // Z takes no numbers: a number after it would loop.
            command = 0;
            continue;
        case 'M':
            if (!OMSVGScanNumbers(&scanner, v, 2)) {
                return path;
            }
            current = NSMakePoint(base.x + v[0], base.y + v[1]);
            [path moveToPoint:current];
            start = current;
            // Further pairs after M are line-tos.
            command = relative ? 'l' : 'L';
            break;
        case 'L':
            if (!OMSVGScanNumbers(&scanner, v, 2)) {
                return path;
            }
            current = NSMakePoint(base.x + v[0], base.y + v[1]);
            [path lineToPoint:current];
            break;
        case 'H':
            if (!OMSVGScanNumbers(&scanner, v, 1)) {
                return path;
            }
            current.x = (relative ? current.x : 0.0) + v[0];
            [path lineToPoint:current];
            break;
        case 'V':
            if (!OMSVGScanNumbers(&scanner, v, 1)) {
                return path;
            }
            current.y = (relative ? current.y : 0.0) + v[0];
            [path lineToPoint:current];
            break;
        case 'C': {
            if (!OMSVGScanNumbers(&scanner, v, 6)) {
                return path;
            }
            NSPoint c1 = NSMakePoint(base.x + v[0], base.y + v[1]);
            NSPoint c2 = NSMakePoint(base.x + v[2], base.y + v[3]);
            current = NSMakePoint(base.x + v[4], base.y + v[5]);
            [path curveToPoint:current controlPoint1:c1 controlPoint2:c2];
            lastControl = c2;
            break;
        }
        case 'S': {
            if (!OMSVGScanNumbers(&scanner, v, 4)) {
                return path;
            }
            NSPoint c1 = (lastCommand == 'C' || lastCommand == 'S')
                ? NSMakePoint(2.0 * current.x - lastControl.x, 2.0 * current.y - lastControl.y)
                : current;
            NSPoint c2 = NSMakePoint(base.x + v[0], base.y + v[1]);
            current = NSMakePoint(base.x + v[2], base.y + v[3]);
            [path curveToPoint:current controlPoint1:c1 controlPoint2:c2];
            lastControl = c2;
            break;
        }
        case 'Q':
        case 'T': {
            NSPoint q;
            if (upper == 'Q') {
                if (!OMSVGScanNumbers(&scanner, v, 4)) {
                    return path;
                }
                q = NSMakePoint(base.x + v[0], base.y + v[1]);
                v[0] = v[2];
                v[1] = v[3];
            } else {
                if (!OMSVGScanNumbers(&scanner, v, 2)) {
                    return path;
                }
                q = (lastCommand == 'Q' || lastCommand == 'T')
                    ? NSMakePoint(2.0 * current.x - lastControl.x, 2.0 * current.y - lastControl.y)
                    : current;
            }
            NSPoint end = NSMakePoint(base.x + v[0], base.y + v[1]);
            // A quadratic as a cubic: controls two thirds of the way to q.
            NSPoint c1 = NSMakePoint(current.x + 2.0 / 3.0 * (q.x - current.x),
                                     current.y + 2.0 / 3.0 * (q.y - current.y));
            NSPoint c2 = NSMakePoint(end.x + 2.0 / 3.0 * (q.x - end.x),
                                     end.y + 2.0 / 3.0 * (q.y - end.y));
            [path curveToPoint:end controlPoint1:c1 controlPoint2:c2];
            current = end;
            lastControl = q;
            break;
        }
        default:
            // Arcs and anything else: dvisvgm's glyphs don't use them.
            return path;
        }
        lastCommand = upper;
    }
    return path;
}

static CGFloat OMSVGLength(NSString *value)
{
    // "80.40586pt": the number; points are the image's unit.
    return value != nil ? (CGFloat)[value doubleValue] : 0.0;
}

static NSColor *OMSVGColor(NSString *value)
{
    if ([value length] != 7 || [value characterAtIndex:0] != '#') {
        return nil;
    }
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[value substringFromIndex:1]];
    if (![scanner scanHexInt:&rgb]) {
        return nil;
    }
    return [NSColor colorWithCalibratedRed:((rgb >> 16) & 0xff) / 255.0
                                     green:((rgb >> 8) & 0xff) / 255.0
                                      blue:(rgb & 0xff) / 255.0
                                     alpha:1.0];
}

// "translate(a b)", "translate(a,b)", "scale(s)", "matrix(a b c d e f)".
static NSAffineTransform *OMSVGTransform(NSString *value)
{
    NSAffineTransform *transform = [NSAffineTransform transform];
    if ([value length] == 0) {
        return transform;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@" ,\t\n"]];
    while (![scanner isAtEnd]) {
        NSString *name = nil;
        if (![scanner scanUpToString:@"(" intoString:&name] || ![scanner scanString:@"(" intoString:NULL]) {
            break;
        }
        NSString *arguments = nil;
        [scanner scanUpToString:@")" intoString:&arguments];
        [scanner scanString:@")" intoString:NULL];
        CGFloat v[6] = { 0, 0, 0, 0, 0, 0 };
        NSUInteger count = 0;
        const char *bytes = [arguments UTF8String];
        if (bytes != NULL) {
            OMSVGScanner numbers = { bytes, bytes + strlen(bytes) };
            while (count < 6 && OMSVGScanNumber(&numbers, &v[count])) {
                count++;
            }
        }
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSAffineTransform *step = [NSAffineTransform transform];
        if ([name isEqualToString:@"translate"] && count >= 1) {
            [step translateXBy:v[0] yBy:(count >= 2 ? v[1] : 0.0)];
        } else if ([name isEqualToString:@"scale"] && count >= 1) {
            [step scaleXBy:v[0] yBy:(count >= 2 ? v[1] : v[0])];
        } else if ([name isEqualToString:@"matrix"] && count == 6) {
            NSAffineTransformStruct m = { v[0], v[1], v[2], v[3], v[4], v[5] };
            [step setTransformStruct:m];
        }
        [step appendTransform:transform];
        transform = step;
    }
    return transform;
}

// Reads the subset: glyph paths in <defs>, drawn by <use>, plus <rect> rules
// and plain <path>s, under <g> transforms.
@interface OMMathSVGReader : NSObject <NSXMLParserDelegate>
{
@public
    NSMutableDictionary *definitions;  // id -> NSBezierPath
    NSMutableArray *uses;              // NSDictionary: href, transform
    NSMutableArray *paths;             // NSBezierPath, ready to fill
    NSMutableArray *transforms;        // the <g> stack
    NSInteger defsDepth;
    NSRect viewBox;
    NSSize size;
    NSColor *ink;
    BOOL failed;
}
@end

@implementation OMMathSVGReader

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        definitions = [[NSMutableDictionary alloc] init];
        uses = [[NSMutableArray alloc] init];
        paths = [[NSMutableArray alloc] init];
        transforms = [[NSMutableArray alloc] initWithObjects:[NSAffineTransform transform], nil];
    }
    return self;
}

- (void)dealloc
{
    [definitions release];
    [uses release];
    [paths release];
    [transforms release];
    [ink release];
    [super dealloc];
}

- (NSAffineTransform *)currentTransform
{
    return [transforms lastObject];
}

- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)element
       namespaceURI:(NSString *)namespaceURI
      qualifiedName:(NSString *)qualifiedName
         attributes:(NSDictionary *)attributes
{
    if ([element isEqualToString:@"svg"]) {
        size = NSMakeSize(OMSVGLength([attributes objectForKey:@"width"]),
                          OMSVGLength([attributes objectForKey:@"height"]));
        NSArray *box = [[attributes objectForKey:@"viewBox"]
                           componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *numbers = [NSMutableArray array];
        for (NSString *part in box) {
            if ([part length] > 0) {
                [numbers addObject:part];
            }
        }
        if ([numbers count] == 4) {
            viewBox = NSMakeRect([[numbers objectAtIndex:0] doubleValue], [[numbers objectAtIndex:1] doubleValue],
                                 [[numbers objectAtIndex:2] doubleValue], [[numbers objectAtIndex:3] doubleValue]);
        } else {
            viewBox = NSMakeRect(0.0, 0.0, size.width, size.height);
        }
        [ink release];
        ink = [OMSVGColor([attributes objectForKey:@"fill"]) retain];
    } else if ([element isEqualToString:@"defs"]) {
        defsDepth++;
    } else if ([element isEqualToString:@"g"]) {
        NSAffineTransform *transform = [[[self currentTransform] copy] autorelease];
        NSAffineTransform *local = OMSVGTransform([attributes objectForKey:@"transform"]);
        [local appendTransform:transform];
        [transforms addObject:local];
    } else if ([element isEqualToString:@"path"]) {
        NSBezierPath *path = OMMathSVGPathFromData([attributes objectForKey:@"d"]);
        NSString *identifier = [attributes objectForKey:@"id"];
        if (defsDepth > 0 && identifier != nil) {
            [definitions setObject:path forKey:identifier];
        } else if (defsDepth == 0) {
            NSBezierPath *placed = [[path copy] autorelease];
            NSAffineTransform *local = OMSVGTransform([attributes objectForKey:@"transform"]);
            [local appendTransform:[self currentTransform]];
            [placed transformUsingAffineTransform:local];
            [paths addObject:placed];
        }
    } else if ([element isEqualToString:@"use"] && defsDepth == 0) {
        NSString *href = [attributes objectForKey:@"xlink:href"];
        if (href == nil) {
            href = [attributes objectForKey:@"href"];
        }
        if ([href hasPrefix:@"#"]) {
            NSAffineTransform *local = OMSVGTransform([attributes objectForKey:@"transform"]);
            NSAffineTransform *offset = [NSAffineTransform transform];
            [offset translateXBy:[[attributes objectForKey:@"x"] doubleValue]
                             yBy:[[attributes objectForKey:@"y"] doubleValue]];
            [offset appendTransform:local];
            [offset appendTransform:[self currentTransform]];
            [uses addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                [href substringFromIndex:1], @"href", offset, @"transform", nil]];
        }
    } else if ([element isEqualToString:@"rect"] && defsDepth == 0) {
        NSBezierPath *rect = [NSBezierPath bezierPathWithRect:
            NSMakeRect([[attributes objectForKey:@"x"] doubleValue], [[attributes objectForKey:@"y"] doubleValue],
                       [[attributes objectForKey:@"width"] doubleValue], [[attributes objectForKey:@"height"] doubleValue])];
        NSAffineTransform *local = OMSVGTransform([attributes objectForKey:@"transform"]);
        [local appendTransform:[self currentTransform]];
        [rect transformUsingAffineTransform:local];
        [paths addObject:rect];
    }
}

- (void)parser:(NSXMLParser *)parser
    didEndElement:(NSString *)element
     namespaceURI:(NSString *)namespaceURI
    qualifiedName:(NSString *)qualifiedName
{
    if ([element isEqualToString:@"defs"]) {
        defsDepth--;
    } else if ([element isEqualToString:@"g"] && [transforms count] > 1) {
        [transforms removeLastObject];
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)error
{
    failed = YES;
}

@end

NSImage *OMMathImageFromSVGData(NSData *svgData)
{
    if (svgData == nil) {
        return nil;
    }
    NSXMLParser *parser = [[[NSXMLParser alloc] initWithData:svgData] autorelease];
    OMMathSVGReader *reader = [[[OMMathSVGReader alloc] init] autorelease];
    [parser setDelegate:reader];
    if (![parser parse] || reader->failed || reader->size.width <= 0.0 || reader->size.height <= 0.0) {
        return nil;
    }
    // <use>s resolved at the end: dvisvgm puts <defs> first, but needn't.
    for (NSDictionary *use in reader->uses) {
        NSBezierPath *glyph = [reader->definitions objectForKey:[use objectForKey:@"href"]];
        if (glyph == nil) {
            continue;
        }
        NSBezierPath *placed = [[glyph copy] autorelease];
        [placed transformUsingAffineTransform:[use objectForKey:@"transform"]];
        [reader->paths addObject:placed];
    }
    if ([reader->paths count] == 0) {
        return nil;
    }
    OMMathSVGImageRep *rep = [[[OMMathSVGImageRep alloc] initWithPaths:reader->paths
                                                               viewBox:reader->viewBox
                                                                  size:reader->size
                                                                   ink:reader->ink] autorelease];
    NSImage *image = [[[NSImage alloc] initWithSize:reader->size] autorelease];
    // Drawn from its paths each time: a cached copy can composite blank on
    // GNUstep.
    [image setCacheMode:NSImageCacheNever];
    [image addRepresentation:rep];
    return image;
}
