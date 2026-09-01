// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import "OMMermaidERDiagram.h"

NSString * const OMMermaidERDiagramErrorDomain = @"OMMermaidERDiagramErrorDomain";
NSString * const OMMermaidERDiagramErrorLineNumberKey = @"OMMermaidERDiagramErrorLineNumber";

static NSString * const OMMermaidERDiagramHeaderKeyword = @"erDiagram";

@interface OMMermaidERAttribute ()
- (instancetype)initWithType:(NSString *)type
                        name:(NSString *)name
                        keys:(NSArray *)keys
                     comment:(NSString *)comment;
@end

@interface OMMermaidEREntity ()
- (instancetype)initWithName:(NSString *)name displayName:(NSString *)displayName;
- (void)om_setDisplayName:(NSString *)displayName;
- (void)om_addAttribute:(OMMermaidERAttribute *)attribute;
@end

@interface OMMermaidERRelationship ()
- (instancetype)initWithLeftEntityName:(NSString *)leftEntityName
                       rightEntityName:(NSString *)rightEntityName
                       leftCardinality:(OMMermaidERCardinality)leftCardinality
                      rightCardinality:(OMMermaidERCardinality)rightCardinality
                           identifying:(BOOL)identifying
                                 label:(NSString *)label;
@end

@interface OMMermaidERDiagram ()
- (OMMermaidEREntity *)om_entityForName:(NSString *)name displayName:(NSString *)displayName;
- (void)om_addRelationship:(OMMermaidERRelationship *)relationship;
- (BOOL)om_parseSource:(NSString *)source error:(NSError **)error;
- (BOOL)om_parseAttributeLine:(NSString *)trimmedLine
                   lineNumber:(NSUInteger)lineNumber
                       entity:(OMMermaidEREntity *)entity
                        error:(NSError **)error;
- (BOOL)om_parseRelationshipLine:(NSString *)trimmedLine
                      lineNumber:(NSUInteger)lineNumber
                   tokenLocation:(NSUInteger)tokenLocation
                 leftCardinality:(OMMermaidERCardinality)leftCardinality
                rightCardinality:(OMMermaidERCardinality)rightCardinality
                     identifying:(BOOL)identifying
                           error:(NSError **)error;
@end

#pragma mark - Scanning helpers

static BOOL OMMermaidIsWhitespace(unichar ch)
{
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == 0x000B || ch == 0x000C;
}

static NSString *OMMermaidTrimmed(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL OMMermaidLineIsIgnorable(NSString *trimmedLine)
{
    if ([trimmedLine length] == 0) {
        return YES;
    }
    return [trimmedLine hasPrefix:@"%%"];
}

static void OMMermaidSkipWhitespace(NSString *line, NSUInteger *index)
{
    NSUInteger length = [line length];
    while (*index < length && OMMermaidIsWhitespace([line characterAtIndex:*index])) {
        *index += 1;
    }
}

// Reads a double-quoted run starting at *index (which must point at the opening
// quote). Returns NO when the run is unterminated.
static BOOL OMMermaidReadQuotedRun(NSString *line, NSUInteger *index, NSString **valueOut)
{
    NSUInteger length = [line length];
    if (*index >= length || [line characterAtIndex:*index] != '"') {
        return NO;
    }

    NSUInteger cursor = *index + 1;
    NSMutableString *value = [NSMutableString string];
    while (cursor < length) {
        unichar ch = [line characterAtIndex:cursor];
        if (ch == '"') {
            *index = cursor + 1;
            if (valueOut != NULL) {
                *valueOut = value;
            }
            return YES;
        }
        [value appendFormat:@"%C", ch];
        cursor += 1;
    }
    return NO;
}

static BOOL OMMermaidCharacterTerminatesBareName(unichar ch)
{
    return OMMermaidIsWhitespace(ch) ||
           ch == '[' || ch == ']' ||
           ch == '{' || ch == '}' ||
           ch == ':' || ch == '"' ||
           ch == ',';
}

// Parses "NAME", "\"quoted name\"", "NAME[alias]" or "NAME[\"quoted alias\"]".
static BOOL OMMermaidParseEntityReference(NSString *line,
                                          NSUInteger *index,
                                          NSString **nameOut,
                                          NSString **aliasOut)
{
    NSUInteger length = [line length];
    OMMermaidSkipWhitespace(line, index);
    if (*index >= length) {
        return NO;
    }

    NSString *name = nil;
    if ([line characterAtIndex:*index] == '"') {
        if (!OMMermaidReadQuotedRun(line, index, &name)) {
            return NO;
        }
    } else {
        NSUInteger start = *index;
        NSUInteger cursor = start;
        while (cursor < length && !OMMermaidCharacterTerminatesBareName([line characterAtIndex:cursor])) {
            cursor += 1;
        }
        if (cursor == start) {
            return NO;
        }
        name = [line substringWithRange:NSMakeRange(start, cursor - start)];
        *index = cursor;
    }

    if (name == nil || [name length] == 0) {
        return NO;
    }

    NSString *alias = nil;
    if (*index < length && [line characterAtIndex:*index] == '[') {
        NSUInteger cursor = *index + 1;
        if (cursor < length && [line characterAtIndex:cursor] == '"') {
            if (!OMMermaidReadQuotedRun(line, &cursor, &alias)) {
                return NO;
            }
            OMMermaidSkipWhitespace(line, &cursor);
            if (cursor >= length || [line characterAtIndex:cursor] != ']') {
                return NO;
            }
            *index = cursor + 1;
        } else {
            NSRange closing = [line rangeOfString:@"]"
                                          options:0
                                            range:NSMakeRange(cursor, length - cursor)];
            if (closing.location == NSNotFound) {
                return NO;
            }
            alias = OMMermaidTrimmed([line substringWithRange:NSMakeRange(cursor, closing.location - cursor)]);
            if ([alias length] == 0) {
                return NO;
            }
            *index = closing.location + 1;
        }
    }

    if (nameOut != NULL) {
        *nameOut = name;
    }
    if (aliasOut != NULL) {
        *aliasOut = alias;
    }
    return YES;
}

#pragma mark - Cardinality

static BOOL OMMermaidLeftCardinalityForMarker(NSString *marker, OMMermaidERCardinality *cardinalityOut)
{
    OMMermaidERCardinality cardinality;
    if ([marker isEqualToString:@"|o"]) {
        cardinality = OMMermaidERCardinalityZeroOrOne;
    } else if ([marker isEqualToString:@"||"]) {
        cardinality = OMMermaidERCardinalityExactlyOne;
    } else if ([marker isEqualToString:@"}o"]) {
        cardinality = OMMermaidERCardinalityZeroOrMore;
    } else if ([marker isEqualToString:@"}|"]) {
        cardinality = OMMermaidERCardinalityOneOrMore;
    } else {
        return NO;
    }

    if (cardinalityOut != NULL) {
        *cardinalityOut = cardinality;
    }
    return YES;
}

static BOOL OMMermaidRightCardinalityForMarker(NSString *marker, OMMermaidERCardinality *cardinalityOut)
{
    OMMermaidERCardinality cardinality;
    if ([marker isEqualToString:@"o|"]) {
        cardinality = OMMermaidERCardinalityZeroOrOne;
    } else if ([marker isEqualToString:@"||"]) {
        cardinality = OMMermaidERCardinalityExactlyOne;
    } else if ([marker isEqualToString:@"o{"]) {
        cardinality = OMMermaidERCardinalityZeroOrMore;
    } else if ([marker isEqualToString:@"|{"]) {
        cardinality = OMMermaidERCardinalityOneOrMore;
    } else {
        return NO;
    }

    if (cardinalityOut != NULL) {
        *cardinalityOut = cardinality;
    }
    return YES;
}

// Finds the six-character cardinality token (left marker, connector, right
// marker) in a relationship line, skipping over quoted runs so that quoted
// entity names and labels cannot be mistaken for a connector.
static BOOL OMMermaidFindCardinalityToken(NSString *line,
                                          NSUInteger *tokenLocationOut,
                                          OMMermaidERCardinality *leftOut,
                                          OMMermaidERCardinality *rightOut,
                                          BOOL *identifyingOut)
{
    NSUInteger length = [line length];
    if (length < 6) {
        return NO;
    }

    NSUInteger cursor = 0;
    while (cursor + 6 <= length) {
        unichar ch = [line characterAtIndex:cursor];
        if (ch == '"') {
            NSUInteger quoteCursor = cursor;
            if (!OMMermaidReadQuotedRun(line, &quoteCursor, NULL)) {
                return NO;
            }
            cursor = quoteCursor;
            continue;
        }

        NSString *connector = [line substringWithRange:NSMakeRange(cursor + 2, 2)];
        BOOL identifying = [connector isEqualToString:@"--"];
        if (identifying || [connector isEqualToString:@".."]) {
            NSString *leftMarker = [line substringWithRange:NSMakeRange(cursor, 2)];
            NSString *rightMarker = [line substringWithRange:NSMakeRange(cursor + 4, 2)];
            OMMermaidERCardinality left = OMMermaidERCardinalityExactlyOne;
            OMMermaidERCardinality right = OMMermaidERCardinalityExactlyOne;
            if (OMMermaidLeftCardinalityForMarker(leftMarker, &left) &&
                OMMermaidRightCardinalityForMarker(rightMarker, &right)) {
                if (tokenLocationOut != NULL) {
                    *tokenLocationOut = cursor;
                }
                if (leftOut != NULL) {
                    *leftOut = left;
                }
                if (rightOut != NULL) {
                    *rightOut = right;
                }
                if (identifyingOut != NULL) {
                    *identifyingOut = identifying;
                }
                return YES;
            }
        }
        cursor += 1;
    }
    return NO;
}

#pragma mark - Errors

static NSError *OMMermaidError(OMMermaidERDiagramErrorCode code,
                               NSUInteger lineNumber,
                               NSString *description)
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (description != nil) {
        [userInfo setObject:description forKey:NSLocalizedDescriptionKey];
    }
    if (lineNumber > 0) {
        [userInfo setObject:[NSNumber numberWithUnsignedInteger:lineNumber]
                     forKey:OMMermaidERDiagramErrorLineNumberKey];
    }
    return [NSError errorWithDomain:OMMermaidERDiagramErrorDomain
                               code:(NSInteger)code
                           userInfo:userInfo];
}

static BOOL OMMermaidFail(NSError **error,
                          OMMermaidERDiagramErrorCode code,
                          NSUInteger lineNumber,
                          NSString *description)
{
    if (error != NULL) {
        *error = OMMermaidError(code, lineNumber, description);
    }
    return NO;
}

#pragma mark - OMMermaidERAttribute

@implementation OMMermaidERAttribute

@synthesize type = _type;
@synthesize name = _name;
@synthesize keys = _keys;
@synthesize comment = _comment;

- (instancetype)initWithType:(NSString *)type
                        name:(NSString *)name
                        keys:(NSArray *)keys
                     comment:(NSString *)comment
{
    self = [super init];
    if (self != nil) {
        _type = [type copy];
        _name = [name copy];
        _keys = [(keys != nil ? keys : [NSArray array]) copy];
        _comment = [comment copy];
    }
    return self;
}

- (void)dealloc
{
    [_type release];
    [_name release];
    [_keys release];
    [_comment release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ %@ keys=%@ comment=%@>",
            NSStringFromClass([self class]),
            _type,
            _name,
            [_keys componentsJoinedByString:@","],
            _comment != nil ? _comment : @"(none)"];
}

@end

#pragma mark - OMMermaidEREntity

@implementation OMMermaidEREntity

@synthesize name = _name;
@synthesize displayName = _displayName;

- (instancetype)initWithName:(NSString *)name displayName:(NSString *)displayName
{
    self = [super init];
    if (self != nil) {
        _name = [name copy];
        _displayName = [(displayName != nil ? displayName : name) copy];
        _attributes = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_name release];
    [_displayName release];
    [_attributes release];
    [super dealloc];
}

- (NSArray *)attributes
{
    return [[_attributes copy] autorelease];
}

- (void)om_setDisplayName:(NSString *)displayName
{
    if (displayName == nil || [displayName length] == 0) {
        return;
    }
    if (displayName == _displayName) {
        return;
    }
    [_displayName release];
    _displayName = [displayName copy];
}

- (void)om_addAttribute:(OMMermaidERAttribute *)attribute
{
    if (attribute != nil) {
        [_attributes addObject:attribute];
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ attributes=%lu>",
            NSStringFromClass([self class]),
            _name,
            (unsigned long)[_attributes count]];
}

@end

#pragma mark - OMMermaidERRelationship

@implementation OMMermaidERRelationship

@synthesize leftEntityName = _leftEntityName;
@synthesize rightEntityName = _rightEntityName;
@synthesize leftCardinality = _leftCardinality;
@synthesize rightCardinality = _rightCardinality;
@synthesize identifying = _identifying;
@synthesize label = _label;

- (instancetype)initWithLeftEntityName:(NSString *)leftEntityName
                       rightEntityName:(NSString *)rightEntityName
                       leftCardinality:(OMMermaidERCardinality)leftCardinality
                      rightCardinality:(OMMermaidERCardinality)rightCardinality
                           identifying:(BOOL)identifying
                                 label:(NSString *)label
{
    self = [super init];
    if (self != nil) {
        _leftEntityName = [leftEntityName copy];
        _rightEntityName = [rightEntityName copy];
        _leftCardinality = leftCardinality;
        _rightCardinality = rightCardinality;
        _identifying = identifying;
        _label = [(label != nil ? label : @"") copy];
    }
    return self;
}

- (void)dealloc
{
    [_leftEntityName release];
    [_rightEntityName release];
    [_label release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ -> %@ label=%@>",
            NSStringFromClass([self class]),
            _leftEntityName,
            _rightEntityName,
            _label];
}

@end

#pragma mark - OMMermaidERDiagram

@implementation OMMermaidERDiagram

+ (BOOL)sourceDeclaresERDiagram:(NSString *)source
{
    if (source == nil || [source length] == 0) {
        return NO;
    }

    NSArray *lines = [source componentsSeparatedByString:@"\n"];
    for (NSString *rawLine in lines) {
        NSString *trimmed = OMMermaidTrimmed(rawLine);
        if (OMMermaidLineIsIgnorable(trimmed)) {
            continue;
        }
        return [trimmed isEqualToString:OMMermaidERDiagramHeaderKeyword];
    }
    return NO;
}

+ (instancetype)diagramWithSource:(NSString *)source error:(NSError **)error
{
    if (error != NULL) {
        *error = nil;
    }
    if (source == nil) {
        OMMermaidFail(error,
                      OMMermaidERDiagramErrorMissingHeader,
                      0,
                      @"Empty diagram source.");
        return nil;
    }

    OMMermaidERDiagram *diagram = [[[self alloc] init] autorelease];
    if (![diagram om_parseSource:source error:error]) {
        return nil;
    }
    return diagram;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _entities = [[NSMutableArray alloc] init];
        _relationships = [[NSMutableArray alloc] init];
        _entitiesByName = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_entities release];
    [_relationships release];
    [_entitiesByName release];
    [super dealloc];
}

- (NSArray *)entities
{
    return [[_entities copy] autorelease];
}

- (NSArray *)relationships
{
    return [[_relationships copy] autorelease];
}

- (OMMermaidEREntity *)entityNamed:(NSString *)name
{
    if (name == nil) {
        return nil;
    }
    return [_entitiesByName objectForKey:name];
}

- (OMMermaidEREntity *)om_entityForName:(NSString *)name displayName:(NSString *)displayName
{
    OMMermaidEREntity *existing = [_entitiesByName objectForKey:name];
    if (existing != nil) {
        [existing om_setDisplayName:displayName];
        return existing;
    }

    OMMermaidEREntity *entity = [[[OMMermaidEREntity alloc] initWithName:name
                                                            displayName:displayName] autorelease];
    [_entities addObject:entity];
    [_entitiesByName setObject:entity forKey:name];
    return entity;
}

- (void)om_addRelationship:(OMMermaidERRelationship *)relationship
{
    if (relationship != nil) {
        [_relationships addObject:relationship];
    }
}

#pragma mark Parsing

- (BOOL)om_parseAttributeLine:(NSString *)trimmedLine
                   lineNumber:(NSUInteger)lineNumber
                       entity:(OMMermaidEREntity *)entity
                        error:(NSError **)error
{
    NSString *declaration = trimmedLine;
    NSString *comment = nil;

    NSRange quoteRange = [trimmedLine rangeOfString:@"\""];
    if (quoteRange.location != NSNotFound) {
        NSUInteger cursor = quoteRange.location;
        if (!OMMermaidReadQuotedRun(trimmedLine, &cursor, &comment)) {
            return OMMermaidFail(error,
                                 OMMermaidERDiagramErrorMalformedAttribute,
                                 lineNumber,
                                 @"Unterminated attribute comment.");
        }
        if ([OMMermaidTrimmed([trimmedLine substringFromIndex:cursor]) length] > 0) {
            return OMMermaidFail(error,
                                 OMMermaidERDiagramErrorMalformedAttribute,
                                 lineNumber,
                                 @"Unexpected text after attribute comment.");
        }
        declaration = [trimmedLine substringToIndex:quoteRange.location];
    }

    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *candidate in [declaration componentsSeparatedByCharactersInSet:
                                     [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if ([candidate length] > 0) {
            [tokens addObject:candidate];
        }
    }

    if ([tokens count] < 2) {
        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorMalformedAttribute,
                             lineNumber,
                             @"Attribute needs a type and a name.");
    }

    NSString *type = [tokens objectAtIndex:0];
    NSString *name = [tokens objectAtIndex:1];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSUInteger index = 2; index < [tokens count]; index++) {
        NSString *token = [tokens objectAtIndex:index];
        for (NSString *keyCandidate in [token componentsSeparatedByString:@","]) {
            NSString *key = [OMMermaidTrimmed(keyCandidate) uppercaseString];
            if ([key length] == 0) {
                continue;
            }
            if (![key isEqualToString:@"PK"] &&
                ![key isEqualToString:@"FK"] &&
                ![key isEqualToString:@"UK"]) {
                return OMMermaidFail(error,
                                     OMMermaidERDiagramErrorMalformedAttribute,
                                     lineNumber,
                                     [NSString stringWithFormat:
                                         @"Unrecognized attribute key \"%@\".", keyCandidate]);
            }
            [keys addObject:key];
        }
    }

    OMMermaidERAttribute *attribute = [[[OMMermaidERAttribute alloc] initWithType:type
                                                                            name:name
                                                                            keys:keys
                                                                         comment:comment] autorelease];
    [entity om_addAttribute:attribute];
    return YES;
}

- (BOOL)om_parseRelationshipLine:(NSString *)trimmedLine
                      lineNumber:(NSUInteger)lineNumber
                   tokenLocation:(NSUInteger)tokenLocation
                 leftCardinality:(OMMermaidERCardinality)leftCardinality
                rightCardinality:(OMMermaidERCardinality)rightCardinality
                     identifying:(BOOL)identifying
                           error:(NSError **)error
{
    NSString *leftSource = [trimmedLine substringToIndex:tokenLocation];
    NSUInteger leftCursor = 0;
    NSString *leftName = nil;
    NSString *leftAlias = nil;
    if (!OMMermaidParseEntityReference(leftSource, &leftCursor, &leftName, &leftAlias)) {
        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorMalformedRelationship,
                             lineNumber,
                             @"Missing entity on the left of the relationship.");
    }
    OMMermaidSkipWhitespace(leftSource, &leftCursor);
    if (leftCursor < [leftSource length]) {
        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorMalformedRelationship,
                             lineNumber,
                             @"Unexpected text before the relationship cardinality.");
    }

    NSString *rightSource = [trimmedLine substringFromIndex:tokenLocation + 6];
    NSUInteger rightCursor = 0;
    NSString *rightName = nil;
    NSString *rightAlias = nil;
    if (!OMMermaidParseEntityReference(rightSource, &rightCursor, &rightName, &rightAlias)) {
        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorMalformedRelationship,
                             lineNumber,
                             @"Missing entity on the right of the relationship.");
    }

    OMMermaidSkipWhitespace(rightSource, &rightCursor);
    NSString *label = @"";
    if (rightCursor < [rightSource length]) {
        if ([rightSource characterAtIndex:rightCursor] != ':') {
            return OMMermaidFail(error,
                                 OMMermaidERDiagramErrorMalformedRelationship,
                                 lineNumber,
                                 @"Expected \":\" before the relationship label.");
        }
        rightCursor += 1;
        OMMermaidSkipWhitespace(rightSource, &rightCursor);
        if (rightCursor < [rightSource length] && [rightSource characterAtIndex:rightCursor] == '"') {
            NSString *quotedLabel = nil;
            if (!OMMermaidReadQuotedRun(rightSource, &rightCursor, &quotedLabel)) {
                return OMMermaidFail(error,
                                     OMMermaidERDiagramErrorMalformedRelationship,
                                     lineNumber,
                                     @"Unterminated relationship label.");
            }
            if ([OMMermaidTrimmed([rightSource substringFromIndex:rightCursor]) length] > 0) {
                return OMMermaidFail(error,
                                     OMMermaidERDiagramErrorMalformedRelationship,
                                     lineNumber,
                                     @"Unexpected text after the relationship label.");
            }
            label = quotedLabel;
        } else {
            label = OMMermaidTrimmed([rightSource substringFromIndex:rightCursor]);
        }
    }

    [self om_entityForName:leftName displayName:leftAlias];
    [self om_entityForName:rightName displayName:rightAlias];

    OMMermaidERRelationship *relationship =
        [[[OMMermaidERRelationship alloc] initWithLeftEntityName:leftName
                                                rightEntityName:rightName
                                                leftCardinality:leftCardinality
                                               rightCardinality:rightCardinality
                                                    identifying:identifying
                                                          label:label] autorelease];
    [self om_addRelationship:relationship];
    return YES;
}

- (BOOL)om_parseSource:(NSString *)source error:(NSError **)error
{
    NSArray *lines = [source componentsSeparatedByString:@"\n"];
    BOOL sawHeader = NO;
    OMMermaidEREntity *openEntity = nil;
    NSUInteger openEntityLineNumber = 0;

    NSUInteger lineNumber = 0;
    for (NSString *rawLine in lines) {
        lineNumber += 1;
        NSString *trimmed = OMMermaidTrimmed(rawLine);
        if (OMMermaidLineIsIgnorable(trimmed)) {
            continue;
        }

        if (!sawHeader) {
            if (![trimmed isEqualToString:OMMermaidERDiagramHeaderKeyword]) {
                return OMMermaidFail(error,
                                     OMMermaidERDiagramErrorMissingHeader,
                                     lineNumber,
                                     @"Diagram does not start with \"erDiagram\".");
            }
            sawHeader = YES;
            continue;
        }

        if (openEntity != nil) {
            if ([trimmed isEqualToString:@"}"]) {
                openEntity = nil;
                openEntityLineNumber = 0;
                continue;
            }
            if (![self om_parseAttributeLine:trimmed
                                  lineNumber:lineNumber
                                      entity:openEntity
                                       error:error]) {
                return NO;
            }
            continue;
        }

        NSUInteger tokenLocation = 0;
        OMMermaidERCardinality leftCardinality = OMMermaidERCardinalityExactlyOne;
        OMMermaidERCardinality rightCardinality = OMMermaidERCardinalityExactlyOne;
        BOOL identifying = YES;
        if (OMMermaidFindCardinalityToken(trimmed,
                                          &tokenLocation,
                                          &leftCardinality,
                                          &rightCardinality,
                                          &identifying)) {
            if (![self om_parseRelationshipLine:trimmed
                                     lineNumber:lineNumber
                                  tokenLocation:tokenLocation
                                leftCardinality:leftCardinality
                               rightCardinality:rightCardinality
                                    identifying:identifying
                                          error:error]) {
                return NO;
            }
            continue;
        }

        NSUInteger cursor = 0;
        NSString *entityName = nil;
        NSString *entityAlias = nil;
        if (!OMMermaidParseEntityReference(trimmed, &cursor, &entityName, &entityAlias)) {
            return OMMermaidFail(error,
                                 OMMermaidERDiagramErrorUnsupportedStatement,
                                 lineNumber,
                                 @"Unsupported erDiagram statement.");
        }

        OMMermaidSkipWhitespace(trimmed, &cursor);
        NSString *remainder = [trimmed substringFromIndex:cursor];
        if ([remainder isEqualToString:@"{"]) {
            openEntity = [self om_entityForName:entityName displayName:entityAlias];
            openEntityLineNumber = lineNumber;
            continue;
        }
        if ([remainder length] == 0) {
            [self om_entityForName:entityName displayName:entityAlias];
            continue;
        }

        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorMalformedEntity,
                             lineNumber,
                             @"Expected \"{\" or end of line after an entity name.");
    }

    if (!sawHeader) {
        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorMissingHeader,
                             0,
                             @"Diagram does not start with \"erDiagram\".");
    }
    if (openEntity != nil) {
        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorUnterminatedEntityBlock,
                             openEntityLineNumber,
                             @"Entity block is missing a closing \"}\".");
    }
    if ([_entities count] == 0) {
        return OMMermaidFail(error,
                             OMMermaidERDiagramErrorEmptyDiagram,
                             0,
                             @"Diagram declares no entities.");
    }
    return YES;
}

@end
