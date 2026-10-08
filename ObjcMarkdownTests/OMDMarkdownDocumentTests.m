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

// A file in a fresh temporary folder, with data.
- (NSString *)temporaryFileNamed:(NSString *)name data:(NSData *)data
{
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"omd-document-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [folder stringByAppendingPathComponent:name];
    [data writeToFile:path atomically:YES];
    return path;
}

- (void)testReadsMarkdownAsMarkdownAndCodeVerbatim
{
    NSString *markdown = [self temporaryFileNamed:@"notes.md"
                                             data:[@"# Notes\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *text = nil;
    OMDDocumentRenderMode mode = OMDDocumentRenderModeVerbatim;
    NSString *syntax = @"unset";
    XCTAssertTrue([OMDMarkdownDocument readTextFileAtPath:markdown text:&text renderMode:&mode syntaxLanguage:&syntax error:NULL]);
    XCTAssertEqualObjects(text, @"# Notes\n");
    XCTAssertEqual(mode, OMDDocumentRenderModeMarkdown);
    XCTAssertNil(syntax);

    NSString *python = [self temporaryFileNamed:@"tool.py"
                                           data:[@"print('hi')\n" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertTrue([OMDMarkdownDocument readTextFileAtPath:python text:&text renderMode:&mode syntaxLanguage:&syntax error:NULL]);
    XCTAssertEqualObjects(text, @"print('hi')\n");
    XCTAssertEqual(mode, OMDDocumentRenderModeVerbatim);
    XCTAssertEqualObjects(syntax, @"python");
}

- (void)testReadsOtherEncodingsAndRefusesBinaryFiles
{
    const char latin1[] = { 'c', 'a', 'f', (char)0xE9, '\n' };
    NSString *path = [self temporaryFileNamed:@"cafe.md" data:[NSData dataWithBytes:latin1 length:sizeof(latin1)]];
    NSString *text = nil;
    XCTAssertTrue([OMDMarkdownDocument readTextFileAtPath:path text:&text renderMode:NULL syntaxLanguage:NULL error:NULL]);
    XCTAssertEqualObjects(text, @"caf\u00E9\n");

    const char binary[] = { 'P', 'K', 3, 4, 0, 0, 0, 0, 1, 2 };
    NSString *binaryPath = [self temporaryFileNamed:@"archive.md" data:[NSData dataWithBytes:binary length:sizeof(binary)]];
    NSError *error = nil;
    XCTAssertFalse([OMDMarkdownDocument readTextFileAtPath:binaryPath text:&text renderMode:NULL syntaxLanguage:NULL error:&error]);
    XCTAssertEqualObjects([error domain], OMDTextFileErrorDomain);
    XCTAssertEqual([error code], (NSInteger)2);

    XCTAssertFalse([OMDMarkdownDocument readTextFileAtPath:[path stringByAppendingString:@".missing"]
                                                      text:&text renderMode:NULL syntaxLanguage:NULL error:&error]);
    XCTAssertEqual([error code], (NSInteger)4);
}

- (void)testReadsAndWritesThroughNSDocument
{
    NSString *path = [self temporaryFileNamed:@"readme.md"
                                         data:[@"Hello\n" dataUsingEncoding:NSUTF8StringEncoding]];
    OMDMarkdownDocument *document = [[[OMDMarkdownDocument alloc] init] autorelease];
    NSError *error = nil;
    XCTAssertTrue([document readFromURL:[NSURL fileURLWithPath:path] ofType:@"net.daringfireball.markdown" error:&error]);
    XCTAssertEqualObjects([document markdown], @"Hello\n");
    XCTAssertEqual([document renderMode], OMDDocumentRenderModeMarkdown);
    XCTAssertTrue([[document loadedDiskFingerprint] length] > 0);
    XCTAssertEqualObjects([document observedDiskFingerprint], [document loadedDiskFingerprint]);

    [document setMarkdown:@"caf\u00E9"];
    NSData *data = [document dataOfType:@"net.daringfireball.markdown" error:&error];
    XCTAssertEqualObjects([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease], @"caf\u00E9");
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
