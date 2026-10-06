// ObjcMarkdown
// SPDX-License-Identifier: LGPL-2.1-or-later

#import <Foundation/Foundation.h>
#import "OMExport.h"

OM_EXPORT NSString * const OMMermaidERDiagramErrorDomain;

// NSNumber, 1-based line number within the diagram source.
OM_EXPORT NSString * const OMMermaidERDiagramErrorLineNumberKey;

typedef NS_ENUM(NSInteger, OMMermaidERDiagramErrorCode) {
    OMMermaidERDiagramErrorMissingHeader = 1,
    OMMermaidERDiagramErrorEmptyDiagram = 2,
    OMMermaidERDiagramErrorMalformedRelationship = 3,
    OMMermaidERDiagramErrorMalformedEntity = 4,
    OMMermaidERDiagramErrorMalformedAttribute = 5,
    OMMermaidERDiagramErrorUnterminatedEntityBlock = 6,
    OMMermaidERDiagramErrorUnsupportedStatement = 7
};

// Crow's-foot cardinality for one end of a relationship.
typedef NS_ENUM(NSInteger, OMMermaidERCardinality) {
    OMMermaidERCardinalityZeroOrOne = 0,
    OMMermaidERCardinalityExactlyOne = 1,
    OMMermaidERCardinalityZeroOrMore = 2,
    OMMermaidERCardinalityOneOrMore = 3
};

@interface OMMermaidERAttribute : NSObject
{
    NSString *_type;
    NSString *_name;
    NSArray *_keys;
    NSString *_comment;
}

// Declared type, verbatim from the source (for example "uuid" or "char(2)").
@property (nonatomic, readonly) NSString *type;
@property (nonatomic, readonly) NSString *name;
// Uppercased key markers in source order: "PK", "FK", "UK".
@property (nonatomic, readonly) NSArray *keys;
// Trailing quoted comment, or nil.
@property (nonatomic, readonly) NSString *comment;

@end

@interface OMMermaidEREntity : NSObject
{
    NSString *_name;
    NSString *_displayName;
    NSMutableArray *_attributes;
}

// Identity used by relationships.
@property (nonatomic, readonly) NSString *name;
// Bracket alias when the source supplied one, otherwise the name.
@property (nonatomic, readonly) NSString *displayName;
// OMMermaidERAttribute, in source order.
@property (nonatomic, readonly) NSArray *attributes;

@end

@interface OMMermaidERRelationship : NSObject
{
    NSString *_leftEntityName;
    NSString *_rightEntityName;
    OMMermaidERCardinality _leftCardinality;
    OMMermaidERCardinality _rightCardinality;
    BOOL _identifying;
    NSString *_label;
}

@property (nonatomic, readonly) NSString *leftEntityName;
@property (nonatomic, readonly) NSString *rightEntityName;
@property (nonatomic, readonly) OMMermaidERCardinality leftCardinality;
@property (nonatomic, readonly) OMMermaidERCardinality rightCardinality;
// YES for "--" (identifying), NO for ".." (non-identifying).
@property (nonatomic, readonly, getter=isIdentifying) BOOL identifying;
// Relationship label; empty string when the source supplied none.
@property (nonatomic, readonly) NSString *label;

@end

@interface OMMermaidERDiagram : NSObject
{
    NSMutableArray *_entities;
    NSMutableArray *_relationships;
    NSMutableDictionary *_entitiesByName;
}

// Cheap check that the first meaningful line declares an erDiagram. Callers use
// this to avoid running the full parser over unrelated mermaid diagram types.
+ (BOOL)sourceDeclaresERDiagram:(NSString *)source;

// Returns nil and fills in error when source is not a supported erDiagram.
+ (instancetype)diagramWithSource:(NSString *)source error:(NSError **)error;

// OMMermaidEREntity, ordered by first appearance in the source.
@property (nonatomic, readonly) NSArray *entities;
// OMMermaidERRelationship, in source order.
@property (nonatomic, readonly) NSArray *relationships;

- (OMMermaidEREntity *)entityNamed:(NSString *)name;

@end
