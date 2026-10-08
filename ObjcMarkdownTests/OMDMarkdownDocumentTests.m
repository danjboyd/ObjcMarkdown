// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "OMDMarkdownDocument.h"
#import "OMTestPaths.h"

@interface OMDMarkdownDocumentTests : XCTestCase
{
    NSUInteger _editedStateChanges;
}
@end

@implementation OMDMarkdownDocumentTests

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
    _editedStateChanges = 0;
}

- (void)editedStateDidChange:(NSNotification *)notification
{
    (void)notification;
    _editedStateChanges += 1;
}

// An edit's undo action, which registers itself again so it can be redone.
- (void)undoableChange:(OMDMarkdownDocument *)document
{
    [[document undoManager] registerUndoWithTarget:self selector:@selector(undoableChange:) object:document];
}

// Lets the run loop turn: macOS counts a change then; GNUstep at once.
- (void)settle
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

// One undoable change, as the editor makes for an edit.
- (void)registerUndoableChangeInDocument:(OMDMarkdownDocument *)document
{
    NSUndoManager *undoManager = [document undoManager];
    [undoManager beginUndoGrouping];
    [self undoableChange:document];
    [undoManager endUndoGrouping];
    [self settle];
}

- (void)testSourcePathIsTheFileURL
{
    OMDMarkdownDocument *document = [[[OMDMarkdownDocument alloc] init] autorelease];
    XCTAssertNil([document sourcePath]);
    XCTAssertEqualObjects([document tabTitle], @"Untitled");

    NSString *path = OMTestAbsolutePath(@"/tmp/notes/readme.md");
    [document setSourcePath:path];
    XCTAssertEqualObjects([document sourcePath], path);
    XCTAssertEqualObjects([[document fileURL] path], path);
    XCTAssertEqualObjects([document tabTitle], @"readme.md");

    [document setDisplayTitle:@"Notes"];
    XCTAssertEqualObjects([document tabTitle], @"Notes");

    [document setSourcePath:@" "];
    XCTAssertNil([document sourcePath]);
    XCTAssertNil([document fileURL]);
}

- (void)testEachDocumentHasItsOwnUndoHistory
{
    OMDMarkdownDocument *first = [[[OMDMarkdownDocument alloc] init] autorelease];
    OMDMarkdownDocument *second = [[[OMDMarkdownDocument alloc] init] autorelease];
    XCTAssertNotNil([first undoManager]);
    XCTAssertTrue([first undoManager] != [second undoManager]);

    [self registerUndoableChangeInDocument:first];
    XCTAssertTrue([[first undoManager] canUndo]);
    XCTAssertFalse([[second undoManager] canUndo]);
}

- (void)testUndoingBackToTheSavedTextLeavesNoUnsavedChanges
{
    OMDMarkdownDocument *document = [[[OMDMarkdownDocument alloc] init] autorelease];
    XCTAssertFalse([document isDocumentEdited]);

    [self registerUndoableChangeInDocument:document];
    XCTAssertTrue([document isDocumentEdited]);

    [[document undoManager] undo];
    [self settle];
    XCTAssertFalse([document isDocumentEdited]);

    [[document undoManager] redo];
    [self settle];
    XCTAssertTrue([document isDocumentEdited]);

    [document markSaved];
    XCTAssertFalse([document isDocumentEdited]);
}

- (void)testChangesOutsideUndoStayUnsavedUntilSaved
{
    // As for text restored from a recovery snapshot.
    OMDMarkdownDocument *document = [[[OMDMarkdownDocument alloc] init] autorelease];
    [document markChangedOutsideUndo];
    XCTAssertTrue([document isDocumentEdited]);
    [self registerUndoableChangeInDocument:document];
    [[document undoManager] undo];
    [self settle];
    XCTAssertTrue([document isDocumentEdited]);

    [document markSaved];
    XCTAssertFalse([document isDocumentEdited]);
}

- (void)testNotifiesOnlyWhenUnsavedChangesComeOrGo
{
    OMDMarkdownDocument *document = [[[OMDMarkdownDocument alloc] init] autorelease];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(editedStateDidChange:)
                                                 name:OMDMarkdownDocumentEditedStateDidChangeNotification
                                               object:document];

    [self registerUndoableChangeInDocument:document];
    XCTAssertEqual(_editedStateChanges, (NSUInteger)1);
    [self registerUndoableChangeInDocument:document];
    XCTAssertEqual(_editedStateChanges, (NSUInteger)1);
    [document markSaved];
    XCTAssertEqual(_editedStateChanges, (NSUInteger)2);
    [document markSaved];
    XCTAssertEqual(_editedStateChanges, (NSUInteger)2);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
