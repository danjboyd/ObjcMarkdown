// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMermaidFlowchart.h"
#include <ctype.h>

NSString * const OMMermaidFlowchartErrorDomain = @"OMMermaidFlowchartErrorDomain";
NSString * const OMMermaidFlowchartErrorLineNumberKey = @"OMMermaidFlowchartErrorLineNumber";

// Past these the drawing is unreadable; the source shows instead.
static const NSUInteger OMMermaidFlowchartMaximumNodes = 80;
static const NSUInteger OMMermaidFlowchartMaximumEdges = 160;

@interface OMMermaidFlowNode ()
- (instancetype)initWithIdentifier:(NSString *)identifier;
- (void)setLabel:(NSString *)label shape:(OMMermaidFlowNodeShape)shape;
- (void)addClassName:(NSString *)className;
- (NSArray *)classNames;
- (void)setStyleProperties:(NSDictionary *)properties;
@end

@interface OMMermaidFlowSubgraph ()
- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title parent:(NSString *)parent;
- (void)addNodeIdentifier:(NSString *)identifier;
- (void)addClassName:(NSString *)className;
- (NSArray *)classNames;
- (void)setStyleProperties:(NSDictionary *)properties;
@end

@implementation OMMermaidFlowNode

@synthesize identifier = _identifier;
@synthesize label = _label;
@synthesize shape = _shape;
@synthesize styleProperties = _styleProperties;

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    self = [super init];
    if (self != nil) {
        _identifier = [identifier copy];
        _label = [identifier copy];
        _shape = OMMermaidFlowNodeShapeRectangle;
    }
    return self;
}

- (void)dealloc
{
    [_identifier release];
    [_label release];
    [_classNames release];
    [_styleProperties release];
    [super dealloc];
}

- (void)setLabel:(NSString *)label shape:(OMMermaidFlowNodeShape)shape
{
    NSString *copied = [label copy];
    [_label release];
    _label = copied;
    _shape = shape;
}

- (void)addClassName:(NSString *)className
{
    if (_classNames == nil) {
        _classNames = [[NSMutableArray alloc] init];
    }
    [_classNames addObject:className];
}

- (NSArray *)classNames
{
    return _classNames;
}

- (void)setStyleProperties:(NSDictionary *)properties
{
    NSDictionary *copied = [properties count] > 0 ? [properties copy] : nil;
    [_styleProperties release];
    _styleProperties = copied;
}

@end

@implementation OMMermaidFlowSubgraph

@synthesize identifier = _identifier;
@synthesize title = _title;
@synthesize parentIdentifier = _parentIdentifier;
@synthesize nodeIdentifiers = _nodeIdentifiers;
@synthesize styleProperties = _styleProperties;

- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title parent:(NSString *)parent
{
    self = [super init];
    if (self != nil) {
        _identifier = [identifier copy];
        _title = [title copy];
        _parentIdentifier = [parent copy];
        _nodeIdentifiers = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_identifier release];
    [_title release];
    [_parentIdentifier release];
    [_nodeIdentifiers release];
    [_classNames release];
    [_styleProperties release];
    [super dealloc];
}

- (void)addNodeIdentifier:(NSString *)identifier
{
    [_nodeIdentifiers addObject:identifier];
}

- (void)addClassName:(NSString *)className
{
    if (_classNames == nil) {
        _classNames = [[NSMutableArray alloc] init];
    }
    [_classNames addObject:className];
}

- (NSArray *)classNames
{
    return _classNames;
}

- (void)setStyleProperties:(NSDictionary *)properties
{
    NSDictionary *copied = [properties count] > 0 ? [properties copy] : nil;
    [_styleProperties release];
    _styleProperties = copied;
}

@end

@interface OMMermaidFlowEdge ()
- (instancetype)initFrom:(NSString *)from
                      to:(NSString *)to
                   label:(NSString *)label
                   style:(OMMermaidFlowEdgeStyle)style
                hasArrow:(BOOL)hasArrow;
@end

@implementation OMMermaidFlowEdge

@synthesize fromIdentifier = _fromIdentifier;
@synthesize toIdentifier = _toIdentifier;
@synthesize label = _label;
@synthesize style = _style;
@synthesize hasArrow = _hasArrow;

- (instancetype)initFrom:(NSString *)from
                      to:(NSString *)to
                   label:(NSString *)label
                   style:(OMMermaidFlowEdgeStyle)style
                hasArrow:(BOOL)hasArrow
{
    self = [super init];
    if (self != nil) {
        _fromIdentifier = [from copy];
        _toIdentifier = [to copy];
        _label = [label length] > 0 ? [label copy] : nil;
        _style = style;
        _hasArrow = hasArrow;
    }
    return self;
}

- (void)dealloc
{
    [_fromIdentifier release];
    [_toIdentifier release];
    [_label release];
    [super dealloc];
}

@end

#pragma mark - Parsing

static NSString *OMFlowTrimmed(NSString *text)
{
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// Drops a "%%" comment.
static NSString *OMFlowWithoutComment(NSString *line)
{
    NSRange comment = [line rangeOfString:@"%%"];
    return comment.location == NSNotFound ? line : [line substringToIndex:comment.location];
}

NSString *OMMermaidDeclaredDiagramType(NSString *source)
{
    for (NSString *rawLine in [source componentsSeparatedByString:@"\n"]) {
        NSString *line = OMFlowTrimmed(OMFlowWithoutComment(rawLine));
        if ([line length] == 0 || [line hasPrefix:@"---"]) {
            continue;
        }
        NSRange space = [line rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t;"]];
        return space.location == NSNotFound ? line : [line substringToIndex:space.location];
    }
    return nil;
}

// Splits a line on ";" outside brackets and quotes.
static NSArray *OMFlowStatementsInLine(NSString *line)
{
    NSMutableArray *statements = [NSMutableArray array];
    NSInteger depth = 0;
    BOOL quoted = NO;
    NSUInteger start = 0;
    NSUInteger index = 0;
    for (; index < [line length]; index++) {
        unichar ch = [line characterAtIndex:index];
        if (ch == '"') {
            quoted = !quoted;
        } else if (!quoted && (ch == '[' || ch == '(' || ch == '{')) {
            depth += 1;
        } else if (!quoted && (ch == ']' || ch == ')' || ch == '}')) {
            depth = MAX(0, depth - 1);
        } else if (!quoted && depth == 0 && ch == ';') {
            [statements addObject:[line substringWithRange:NSMakeRange(start, index - start)]];
            start = index + 1;
        }
    }
    [statements addObject:[line substringFromIndex:start]];
    return statements;
}

@interface OMMermaidFlowParser : NSObject
{
@public
    NSMutableArray *_nodes;
    NSMutableDictionary *_nodesByIdentifier;
    NSMutableArray *_edges;
    // Identifiers the current statement mentions, in order.
    NSMutableArray *_mentioned;
    NSString *_text;
    NSUInteger _position;
}
@end

@implementation OMMermaidFlowParser

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _nodes = [[NSMutableArray alloc] init];
        _nodesByIdentifier = [[NSMutableDictionary alloc] init];
        _edges = [[NSMutableArray alloc] init];
        _mentioned = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_nodes release];
    [_nodesByIdentifier release];
    [_edges release];
    [_mentioned release];
    [_text release];
    [super dealloc];
}

- (OMMermaidFlowNode *)nodeForIdentifier:(NSString *)identifier
{
    OMMermaidFlowNode *node = [_nodesByIdentifier objectForKey:identifier];
    if (node == nil) {
        node = [[[OMMermaidFlowNode alloc] initWithIdentifier:identifier] autorelease];
        [_nodesByIdentifier setObject:node forKey:identifier];
        [_nodes addObject:node];
    }
    return node;
}

- (void)skipSpaces
{
    while (_position < [_text length] &&
           [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[_text characterAtIndex:_position]]) {
        _position += 1;
    }
}

- (BOOL)hasPrefix:(NSString *)prefix
{
    return [_text length] - _position >= [prefix length] &&
           [[_text substringWithRange:NSMakeRange(_position, [prefix length])] isEqualToString:prefix];
}

// An identifier: letters, digits, "_", and "-" between them ("A-->B" stops at A).
- (NSString *)parseIdentifier
{
    NSUInteger start = _position;
    NSUInteger length = [_text length];
    while (_position < length) {
        unichar ch = [_text characterAtIndex:_position];
        BOOL word = (ch < 128 && (isalnum((int)ch) || ch == '_')) || (ch >= 128 && [[NSCharacterSet alphanumericCharacterSet] characterIsMember:ch]);
        if (word) {
            _position += 1;
            continue;
        }
        if (ch == '-' && _position > start && _position + 1 < length) {
            unichar next = [_text characterAtIndex:_position + 1];
            if (next < 128 && (isalnum((int)next) || next == '_')) {
                _position += 1;
                continue;
            }
        }
        break;
    }
    return _position > start ? [_text substringWithRange:NSMakeRange(start, _position - start)] : nil;
}

// Text up to closer (honouring a quoted label), or nil if closer never comes.
- (NSString *)parseLabelUntil:(NSString *)closer
{
    [self skipSpaces];
    NSString *label = nil;
    if (_position < [_text length] && [_text characterAtIndex:_position] == '"') {
        NSRange quote = [_text rangeOfString:@"\"" options:0 range:NSMakeRange(_position + 1, [_text length] - _position - 1)];
        if (quote.location == NSNotFound) {
            return nil;
        }
        label = [_text substringWithRange:NSMakeRange(_position + 1, quote.location - _position - 1)];
        _position = NSMaxRange(quote);
        [self skipSpaces];
        if (![self hasPrefix:closer]) {
            return nil;
        }
    } else {
        NSRange close = [_text rangeOfString:closer options:0 range:NSMakeRange(_position, [_text length] - _position)];
        if (close.location == NSNotFound) {
            return nil;
        }
        label = OMFlowTrimmed([_text substringWithRange:NSMakeRange(_position, close.location - _position)]);
        _position = close.location;
    }
    _position += [closer length];
    return label;
}

// A node reference with an optional shape and label; returns its identifier.
- (NSString *)parseNode
{
    [self skipSpaces];
    NSString *identifier = [self parseIdentifier];
    if (identifier == nil) {
        return nil;
    }
    OMMermaidFlowNode *node = [self nodeForIdentifier:identifier];
    [_mentioned addObject:identifier];
    // Opener, closer, shape: longer openers first.
    static const struct { const char *open; const char *close; OMMermaidFlowNodeShape shape; } shapes[] = {
        { "([", "])", OMMermaidFlowNodeShapeStadium },
        { "[[", "]]", OMMermaidFlowNodeShapeSubroutine },
        { "((", "))", OMMermaidFlowNodeShapeCircle },
        { "[(", ")]", OMMermaidFlowNodeShapeRectangle },
        { "{{", "}}", OMMermaidFlowNodeShapeDiamond },
        { "[/", "/]", OMMermaidFlowNodeShapeRectangle },
        { "[\\", "\\]", OMMermaidFlowNodeShapeRectangle },
        { "[", "]", OMMermaidFlowNodeShapeRectangle },
        { "(", ")", OMMermaidFlowNodeShapeRounded },
        { "{", "}", OMMermaidFlowNodeShapeDiamond },
        { ">", "]", OMMermaidFlowNodeShapeRectangle },
    };
    size_t index = 0;
    for (; index < sizeof(shapes) / sizeof(shapes[0]); index++) {
        NSString *open = [NSString stringWithUTF8String:shapes[index].open];
        if (![self hasPrefix:open]) {
            continue;
        }
        _position += [open length];
        NSString *label = [self parseLabelUntil:[NSString stringWithUTF8String:shapes[index].close]];
        if (label == nil) {
            return nil;
        }
        [node setLabel:label shape:shapes[index].shape];
        break;
    }
    if ([self hasPrefix:@":::"]) {
        _position += 3;
        NSString *className = [self parseIdentifier];
        if (className != nil) {
            [node addClassName:className];
        }
    }
    return identifier;
}

- (NSArray *)parseNodeGroup
{
    NSMutableArray *identifiers = [NSMutableArray array];
    while (YES) {
        NSString *identifier = [self parseNode];
        if (identifier == nil) {
            return nil;
        }
        [identifiers addObject:identifier];
        [self skipSpaces];
        if (![self hasPrefix:@"&"]) {
            return identifiers;
        }
        _position += 1;
    }
}

static OMMermaidFlowEdgeStyle OMFlowStyleForToken(NSString *token)
{
    if ([token rangeOfString:@"="].location != NSNotFound) {
        return OMMermaidFlowEdgeStyleThick;
    }
    if ([token rangeOfString:@"."].location != NSNotFound) {
        return OMMermaidFlowEdgeStyleDotted;
    }
    return OMMermaidFlowEdgeStyleSolid;
}

static BOOL OMFlowTokenHasArrow(NSString *token)
{
    return [token hasSuffix:@">"] || [token hasSuffix:@"o"] || [token hasSuffix:@"x"];
}

// A link: "-->", "---", "-.->", "==>" ... with an optional "|label|", or
// "-- label -->" style text labels. Returns NO if none starts here.
- (BOOL)parseLinkStyle:(OMMermaidFlowEdgeStyle *)style hasArrow:(BOOL *)hasArrow label:(NSString **)label
{
    [self skipSpaces];
    NSString *rest = [_text substringFromIndex:_position];
    static NSRegularExpression *arrow = nil;
    static NSRegularExpression *textLabel = nil;
    if (arrow == nil) {
        arrow = [[NSRegularExpression alloc] initWithPattern:@"^<?(-{2,}>|-{3,}|={2,}>|={3,}|-\\.+->|-\\.+-|--[ox])\\s*(?:\\|([^|]*)\\|)?"
                                                     options:0 error:NULL];
        textLabel = [[NSRegularExpression alloc] initWithPattern:@"^<?(--|==|-\\.)\\s*([^\\s>|=.\\-][^|]*?)\\s*(-{2,}>|-{3,}|={2,}>|={3,}|\\.+->|\\.+-)"
                                                         options:0 error:NULL];
    }
    NSTextCheckingResult *match = [arrow firstMatchInString:rest options:0 range:NSMakeRange(0, [rest length])];
    if (match != nil) {
        NSString *token = [rest substringWithRange:[match rangeAtIndex:1]];
        *style = OMFlowStyleForToken(token);
        *hasArrow = OMFlowTokenHasArrow(token);
        *label = [match rangeAtIndex:2].location != NSNotFound
            ? OMFlowTrimmed([rest substringWithRange:[match rangeAtIndex:2]])
            : nil;
        _position += NSMaxRange([match range]);
        return YES;
    }
    match = [textLabel firstMatchInString:rest options:0 range:NSMakeRange(0, [rest length])];
    if (match != nil) {
        NSString *closing = [rest substringWithRange:[match rangeAtIndex:3]];
        *style = OMFlowStyleForToken([[rest substringWithRange:[match rangeAtIndex:1]] stringByAppendingString:closing]);
        *hasArrow = OMFlowTokenHasArrow(closing);
        *label = OMFlowTrimmed([rest substringWithRange:[match rangeAtIndex:2]]);
        if ([*label hasPrefix:@"\""] && [*label hasSuffix:@"\""] && [*label length] >= 2) {
            *label = [*label substringWithRange:NSMakeRange(1, [*label length] - 2)];
        }
        _position += NSMaxRange([match range]);
        return YES;
    }
    return NO;
}

- (BOOL)parseStatement:(NSString *)statement
{
    [_text release];
    _text = [statement copy];
    _position = 0;
    [_mentioned removeAllObjects];
    NSArray *previous = [self parseNodeGroup];
    if (previous == nil) {
        return NO;
    }
    while (YES) {
        [self skipSpaces];
        if (_position >= [_text length]) {
            return YES;
        }
        OMMermaidFlowEdgeStyle style = OMMermaidFlowEdgeStyleSolid;
        BOOL hasArrow = NO;
        NSString *label = nil;
        if (![self parseLinkStyle:&style hasArrow:&hasArrow label:&label]) {
            return NO;
        }
        NSArray *next = [self parseNodeGroup];
        if (next == nil) {
            return NO;
        }
        for (NSString *from in previous) {
            for (NSString *to in next) {
                [_edges addObject:[[[OMMermaidFlowEdge alloc] initFrom:from to:to label:label style:style hasArrow:hasArrow] autorelease]];
            }
        }
        previous = next;
    }
}

@end

// Splits text on separator outside parentheses ("rgb(1,2,3)" stays whole).
static NSArray *OMFlowSplitOutsideParentheses(NSString *text, unichar separator)
{
    NSMutableArray *parts = [NSMutableArray array];
    NSInteger depth = 0;
    NSUInteger start = 0;
    NSUInteger index = 0;
    for (; index < [text length]; index++) {
        unichar ch = [text characterAtIndex:index];
        if (ch == '(') {
            depth += 1;
        } else if (ch == ')') {
            depth = MAX(0, depth - 1);
        } else if (ch == separator && depth == 0) {
            [parts addObject:OMFlowTrimmed([text substringWithRange:NSMakeRange(start, index - start)])];
            start = index + 1;
        }
    }
    [parts addObject:OMFlowTrimmed([text substringFromIndex:start])];
    return parts;
}

// "fill:#f9f,stroke:#333,stroke-width:4px" as {"fill": "#f9f", ...}.
static NSDictionary *OMFlowStyleProperties(NSString *text)
{
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    for (NSString *part in OMFlowSplitOutsideParentheses(text, ',')) {
        NSRange colon = [part rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *key = [OMFlowTrimmed([part substringToIndex:colon.location]) lowercaseString];
        NSString *value = OMFlowTrimmed([part substringFromIndex:NSMaxRange(colon)]);
        if ([key length] > 0 && [value length] > 0) {
            [properties setObject:value forKey:key];
        }
    }
    return properties;
}

// The text after the first word of statement, trimmed.
static NSString *OMFlowRestAfterFirstWord(NSString *statement)
{
    NSRange space = [statement rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
    return space.location == NSNotFound ? @"" : OMFlowTrimmed([statement substringFromIndex:space.location]);
}

static NSString *OMFlowUnquoted(NSString *text)
{
    text = OMFlowTrimmed(text);
    if ([text length] >= 2 && [text hasPrefix:@"\""] && [text hasSuffix:@"\""]) {
        return [text substringWithRange:NSMakeRange(1, [text length] - 2)];
    }
    return text;
}

// "subgraph id[Title]", "subgraph id", "subgraph \"Title\"" or "subgraph Some title".
static BOOL OMFlowSubgraphHeader(NSString *rest, NSString **identifier, NSString **title)
{
    static NSRegularExpression *bracketed = nil;
    if (bracketed == nil) {
        bracketed = [[NSRegularExpression alloc] initWithPattern:@"^([\\w-]+)\\s*\\[(.*)\\]$" options:0 error:NULL];
    }
    NSTextCheckingResult *match = [bracketed firstMatchInString:rest options:0 range:NSMakeRange(0, [rest length])];
    if (match != nil) {
        *identifier = [rest substringWithRange:[match rangeAtIndex:1]];
        *title = OMFlowUnquoted([rest substringWithRange:[match rangeAtIndex:2]]);
        return YES;
    }
    NSString *text = OMFlowUnquoted(rest);
    if ([text length] == 0) {
        return NO;
    }
    *identifier = text;
    *title = text;
    return YES;
}

static NSError *OMFlowError(NSUInteger line, NSString *message)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (line > 0) {
        [info setObject:[NSNumber numberWithUnsignedInteger:line] forKey:OMMermaidFlowchartErrorLineNumberKey];
    }
    return [NSError errorWithDomain:OMMermaidFlowchartErrorDomain code:1 userInfo:info];
}

@implementation OMMermaidFlowchart

@synthesize direction = _direction;
@synthesize nodes = _nodes;
@synthesize edges = _edges;
@synthesize subgraphs = _subgraphs;
@synthesize skippedStatementCount = _skippedStatementCount;
@synthesize clickStatementCount = _clickStatementCount;

+ (BOOL)sourceDeclaresFlowchart:(NSString *)source
{
    NSString *type = OMMermaidDeclaredDiagramType(source);
    return [type isEqualToString:@"flowchart"] || [type isEqualToString:@"graph"];
}

+ (instancetype)flowchartWithSource:(NSString *)source error:(NSError **)error
{
    if (error != NULL) {
        *error = nil;
    }
    OMMermaidFlowchart *chart = [[[self alloc] init] autorelease];
    OMMermaidFlowParser *parser = [[[OMMermaidFlowParser alloc] init] autorelease];
    BOOL sawHeader = NO;
    NSUInteger lineNumber = 0;
    NSSet *skipped = [NSSet setWithObjects:@"linkStyle", @"click", @"direction", @"accTitle", @"accDescr", nil];
    NSMutableArray *subgraphs = [NSMutableArray array];
    NSMutableDictionary *subgraphsByIdentifier = [NSMutableDictionary dictionary];
    NSMutableArray *openSubgraphs = [NSMutableArray array];
    NSMutableSet *groupedNodes = [NSMutableSet set];
    NSMutableDictionary *classDefinitions = [NSMutableDictionary dictionary];
    NSMutableArray *classAssignments = [NSMutableArray array]; // [identifier, class]
    NSMutableArray *styleStatements = [NSMutableArray array];  // [identifier, properties]
    for (NSString *rawLine in [source componentsSeparatedByString:@"\n"]) {
        lineNumber += 1;
        NSString *line = OMFlowTrimmed(OMFlowWithoutComment(rawLine));
        if ([line length] == 0) {
            continue;
        }
        NSArray *statements = OMFlowStatementsInLine(line);
        NSUInteger statementIndex = 0;
        if (!sawHeader) {
            NSArray *words = [OMFlowTrimmed([statements objectAtIndex:0]) componentsSeparatedByCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
            NSString *keyword = [words objectAtIndex:0];
            if (![keyword isEqualToString:@"flowchart"] && ![keyword isEqualToString:@"graph"]) {
                if (error != NULL) {
                    *error = OMFlowError(lineNumber, @"expected \"flowchart\" or \"graph\"");
                }
                return nil;
            }
            NSString *direction = [words count] > 1 ? [[words lastObject] uppercaseString] : @"TD";
            if ([direction isEqualToString:@"LR"]) {
                chart->_direction = OMMermaidFlowDirectionLeftRight;
            } else if ([direction isEqualToString:@"RL"]) {
                chart->_direction = OMMermaidFlowDirectionRightLeft;
            } else if ([direction isEqualToString:@"BT"]) {
                chart->_direction = OMMermaidFlowDirectionBottomUp;
            } else {
                chart->_direction = OMMermaidFlowDirectionTopDown;
            }
            sawHeader = YES;
            statementIndex = 1;
        }
        for (; statementIndex < [statements count]; statementIndex++) {
            NSString *statement = OMFlowTrimmed([statements objectAtIndex:statementIndex]);
            if ([statement length] == 0) {
                continue;
            }
            NSString *firstWord = [[statement componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] objectAtIndex:0];
            if ([firstWord hasSuffix:@":"]) {
                firstWord = [firstWord substringToIndex:[firstWord length] - 1];
            }
            NSString *rest = OMFlowRestAfterFirstWord(statement);
            if ([skipped containsObject:firstWord]) {
                chart->_skippedStatementCount += 1;
                if ([firstWord isEqualToString:@"click"]) {
                    chart->_clickStatementCount += 1;
                }
                continue;
            }
            if ([firstWord isEqualToString:@"subgraph"]) {
                NSString *identifier = nil;
                NSString *title = nil;
                if (!OMFlowSubgraphHeader(rest, &identifier, &title)) {
                    if (error != NULL) {
                        *error = OMFlowError(lineNumber, @"a subgraph needs a name");
                    }
                    return nil;
                }
                OMMermaidFlowSubgraph *subgraph = [subgraphsByIdentifier objectForKey:identifier];
                if (subgraph == nil) {
                    subgraph = [[[OMMermaidFlowSubgraph alloc] initWithIdentifier:identifier
                                                                            title:title
                                                                           parent:[[openSubgraphs lastObject] identifier]] autorelease];
                    [subgraphs addObject:subgraph];
                    [subgraphsByIdentifier setObject:subgraph forKey:identifier];
                }
                [openSubgraphs addObject:subgraph];
                continue;
            }
            if ([firstWord isEqualToString:@"end"] && [rest length] == 0) {
                [openSubgraphs removeLastObject];
                continue;
            }
            if ([firstWord isEqualToString:@"classDef"] || [firstWord isEqualToString:@"class"] ||
                [firstWord isEqualToString:@"style"]) {
                NSRange space = [rest rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([firstWord isEqualToString:@"class"]) {
                    // "class A,B name": the last word is the class.
                    space = [rest rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet] options:NSBackwardsSearch];
                }
                if (space.location == NSNotFound) {
                    chart->_skippedStatementCount += 1;
                    continue;
                }
                NSArray *names = OMFlowSplitOutsideParentheses([rest substringToIndex:space.location], ',');
                NSString *value = OMFlowTrimmed([rest substringFromIndex:space.location]);
                for (NSString *name in names) {
                    if ([name length] == 0) {
                        continue;
                    }
                    if ([firstWord isEqualToString:@"classDef"]) {
                        NSMutableDictionary *definition = [classDefinitions objectForKey:name];
                        if (definition == nil) {
                            definition = [NSMutableDictionary dictionary];
                            [classDefinitions setObject:definition forKey:name];
                        }
                        [definition addEntriesFromDictionary:OMFlowStyleProperties(value)];
                    } else if ([firstWord isEqualToString:@"class"]) {
                        [classAssignments addObject:[NSArray arrayWithObjects:name, value, nil]];
                    } else {
                        [styleStatements addObject:[NSArray arrayWithObjects:name, OMFlowStyleProperties(value), nil]];
                    }
                }
                continue;
            }
            if (![parser parseStatement:statement]) {
                if (error != NULL) {
                    *error = OMFlowError(lineNumber, [NSString stringWithFormat:@"could not read \"%@\"", statement]);
                }
                return nil;
            }
            // A node belongs to the first subgraph it is mentioned in, even
            // if it was mentioned outside before (as in Mermaid).
            OMMermaidFlowSubgraph *open = [openSubgraphs lastObject];
            if (open != nil) {
                for (NSString *identifier in parser->_mentioned) {
                    if (![groupedNodes containsObject:identifier] && [subgraphsByIdentifier objectForKey:identifier] == nil) {
                        [groupedNodes addObject:identifier];
                        [open addNodeIdentifier:identifier];
                    }
                }
            }
        }
    }
    if (!sawHeader) {
        if (error != NULL) {
            *error = OMFlowError(0, @"expected \"flowchart\" or \"graph\"");
        }
        return nil;
    }
    // A link to a subgraph's name ends at the subgraph, not at a node.
    NSUInteger nodeIndex = [parser->_nodes count];
    while (nodeIndex > 0) {
        nodeIndex -= 1;
        if ([subgraphsByIdentifier objectForKey:[[parser->_nodes objectAtIndex:nodeIndex] identifier]] != nil) {
            [parser->_nodes removeObjectAtIndex:nodeIndex];
        }
    }
    // Styles: the "default" class, the node's classes in order, then style lines.
    for (NSArray *assignment in classAssignments) {
        NSString *identifier = [assignment objectAtIndex:0];
        id target = [subgraphsByIdentifier objectForKey:identifier];
        if (target == nil) {
            target = [parser->_nodesByIdentifier objectForKey:identifier];
        }
        [target addClassName:[assignment objectAtIndex:1]];
    }
    for (OMMermaidFlowNode *node in parser->_nodes) {
        NSMutableDictionary *properties = [NSMutableDictionary dictionary];
        NSDictionary *defaults = [classDefinitions objectForKey:@"default"];
        if (defaults != nil) {
            [properties addEntriesFromDictionary:defaults];
        }
        for (NSString *className in [node classNames]) {
            NSDictionary *definition = [classDefinitions objectForKey:className];
            if (definition != nil) {
                [properties addEntriesFromDictionary:definition];
            }
        }
        for (NSArray *styleStatement in styleStatements) {
            if ([[styleStatement objectAtIndex:0] isEqualToString:[node identifier]]) {
                [properties addEntriesFromDictionary:[styleStatement objectAtIndex:1]];
            }
        }
        [node setStyleProperties:properties];
    }
    for (OMMermaidFlowSubgraph *subgraph in subgraphs) {
        NSMutableDictionary *properties = [NSMutableDictionary dictionary];
        for (NSString *className in [subgraph classNames]) {
            NSDictionary *definition = [classDefinitions objectForKey:className];
            if (definition != nil) {
                [properties addEntriesFromDictionary:definition];
            }
        }
        for (NSArray *styleStatement in styleStatements) {
            if ([[styleStatement objectAtIndex:0] isEqualToString:[subgraph identifier]]) {
                [properties addEntriesFromDictionary:[styleStatement objectAtIndex:1]];
            }
        }
        [subgraph setStyleProperties:properties];
    }
    if ([parser->_nodes count] == 0) {
        if (error != NULL) {
            *error = OMFlowError(0, @"no nodes to draw");
        }
        return nil;
    }
    if ([parser->_nodes count] > OMMermaidFlowchartMaximumNodes || [parser->_edges count] > OMMermaidFlowchartMaximumEdges) {
        if (error != NULL) {
            *error = OMFlowError(0, [NSString stringWithFormat:@"too large to draw (%lu nodes, %lu links)",
                                     (unsigned long)[parser->_nodes count], (unsigned long)[parser->_edges count]]);
        }
        return nil;
    }
    chart->_nodes = [parser->_nodes copy];
    chart->_edges = [parser->_edges copy];
    chart->_subgraphs = [subgraphs copy];
    return chart;
}

- (void)dealloc
{
    [_nodes release];
    [_edges release];
    [_subgraphs release];
    [super dealloc];
}

- (OMMermaidFlowSubgraph *)subgraphWithIdentifier:(NSString *)identifier
{
    for (OMMermaidFlowSubgraph *subgraph in _subgraphs) {
        if ([[subgraph identifier] isEqualToString:identifier]) {
            return subgraph;
        }
    }
    return nil;
}

- (OMMermaidFlowNode *)nodeWithIdentifier:(NSString *)identifier
{
    for (OMMermaidFlowNode *node in _nodes) {
        if ([[node identifier] isEqualToString:identifier]) {
            return node;
        }
    }
    return nil;
}

@end
