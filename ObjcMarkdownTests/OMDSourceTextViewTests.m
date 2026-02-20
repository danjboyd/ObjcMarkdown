// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "OMDSourceTextView.h"

@interface OMDSourceTextViewShortcutSpy : OMDSourceTextView
{
    SEL _lastEditorAction;
    BOOL _vimHandled;
    BOOL _vimWasCalled;
}
- (SEL)lastEditorAction;
- (void)setVimHandled:(BOOL)handled;
- (BOOL)vimWasCalled;
@end

@interface OMDSourceTextView (ShortcutTestHooks)
- (BOOL)omdHandleStandardEditingShortcutEvent:(NSEvent *)event;
@end

@interface OMDFakeShortcutEvent : NSObject
{
    NSUInteger _modifierFlags;
    NSString *_charactersIgnoringModifiers;
}
- (id)initWithCharactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
                            modifierFlags:(NSUInteger)modifierFlags;
@end

@implementation OMDSourceTextViewShortcutSpy

- (BOOL)omdSendEditorAction:(SEL)action
{
    _lastEditorAction = action;
    return YES;
}

- (BOOL)omdHandleVimKeyEvent:(NSEvent *)event
{
    (void)event;
    _vimWasCalled = YES;
    return _vimHandled;
}

- (SEL)lastEditorAction
{
    return _lastEditorAction;
}

- (void)setVimHandled:(BOOL)handled
{
    _vimHandled = handled;
}

- (BOOL)vimWasCalled
{
    return _vimWasCalled;
}

@end

@implementation OMDFakeShortcutEvent

- (id)initWithCharactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
                            modifierFlags:(NSUInteger)modifierFlags
{
    self = [super init];
    if (self != nil) {
        _modifierFlags = modifierFlags;
        _charactersIgnoringModifiers = [charactersIgnoringModifiers copy];
    }
    return self;
}

- (void)dealloc
{
    [_charactersIgnoringModifiers release];
    [super dealloc];
}

- (NSUInteger)modifierFlags
{
    return _modifierFlags;
}

- (NSString *)charactersIgnoringModifiers
{
    return _charactersIgnoringModifiers;
}

- (NSString *)characters
{
    return _charactersIgnoringModifiers;
}

@end

@interface OMDSourceTextViewTests : XCTestCase
@end

@implementation OMDSourceTextViewTests

- (OMDSourceTextView *)newSourceView
{
    OMDSourceTextView *view = [[OMDSourceTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    [view setEditable:YES];
    [view setSelectable:YES];
    [view setRichText:NO];
    return view;
}

- (OMDSourceTextViewShortcutSpy *)newShortcutSpyView
{
    OMDSourceTextViewShortcutSpy *view = [[OMDSourceTextViewShortcutSpy alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    [view setEditable:YES];
    [view setSelectable:YES];
    [view setRichText:NO];
    return view;
}

- (NSEvent *)shortcutEventWithCharactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
                                                modifiers:(NSUInteger)modifiers
{
    return (NSEvent *)[[[OMDFakeShortcutEvent alloc] initWithCharactersIgnoringModifiers:charactersIgnoringModifiers
                                                                            modifierFlags:modifiers] autorelease];
}

- (void)testTabIndentsBulletListLine
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"- item"];
    [view setSelectedRange:NSMakeRange(2, 0)];

    [view insertTab:nil];

    XCTAssertEqualObjects([view string], @"    - item");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)6);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

- (void)testBacktabOutdentsBulletListLine
{
    OMDSourceTextView *view = [self newSourceView];
    [view setString:@"    - item"];
    [view setSelectedRange:NSMakeRange(6, 0)];

    [view insertBacktab:nil];

    XCTAssertEqualObjects([view string], @"- item");
    XCTAssertEqual([view selectedRange].location, (NSUInteger)2);
    XCTAssertEqual([view selectedRange].length, (NSUInteger)0);
    [view release];
}

- (void)testTabIndentsEachSelectedListLine
{
    OMDSourceTextView *view = [self newSourceView];
    NSString *source = @"- one\n1. two\nplain\n- three";
    [view setString:source];
    [view setSelectedRange:NSMakeRange(0, [source length])];

    [view insertTab:nil];

    XCTAssertEqualObjects([view string], @"    - one\n    1. two\nplain\n    - three");
    [view release];
}

- (void)testBacktabOutdentsEachSelectedListLine
{
    OMDSourceTextView *view = [self newSourceView];
    NSString *source = @"    - one\n    1. two\nplain\n    - three";
    [view setString:source];
    [view setSelectedRange:NSMakeRange(0, [source length])];

    [view insertBacktab:nil];

    XCTAssertEqualObjects([view string], @"- one\n1. two\nplain\n- three");
    [view release];
}

- (void)testControlEqualsTriggersIncreaseEditorFontAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"="
                                                              modifiers:NSControlKeyMask];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(increaseSourceEditorFontSize:));
    [view release];
}

- (void)testControlShiftEqualsTriggersIncreaseEditorFontAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"="
                                                              modifiers:(NSControlKeyMask | NSShiftKeyMask)];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(increaseSourceEditorFontSize:));
    [view release];
}

- (void)testControlMinusTriggersDecreaseEditorFontAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"-"
                                                              modifiers:NSControlKeyMask];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(decreaseSourceEditorFontSize:));
    [view release];
}

- (void)testControlBTriggersBoldFormattingAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"b"
                                                              modifiers:NSControlKeyMask];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(toggleBoldFormatting:));
    [view release];
}

- (void)testControlITriggersItalicFormattingAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"i"
                                                              modifiers:NSControlKeyMask];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(toggleItalicFormatting:));
    [view release];
}

- (void)testControlCharacterBTriggersBoldFormattingAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSString *controlB = [NSString stringWithFormat:@"%C", (unichar)0x02];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:controlB
                                                              modifiers:NSControlKeyMask];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(toggleBoldFormatting:));
    [view release];
}

- (void)testControlCharacterITriggersItalicFormattingAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSString *controlI = [NSString stringWithFormat:@"%C", (unichar)0x09];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:controlI
                                                              modifiers:NSControlKeyMask];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(toggleItalicFormatting:));
    [view release];
}

- (void)testCommandBTriggersBoldFormattingAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"b"
                                                              modifiers:NSCommandKeyMask];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(toggleBoldFormatting:));
    [view release];
}

- (void)testControlAlternateBStillTriggersBoldFormattingAction
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"b"
                                                              modifiers:(NSControlKeyMask | NSAlternateKeyMask)];

    BOOL handled = [view omdHandleStandardEditingShortcutEvent:event];

    XCTAssertTrue(handled);
    XCTAssertTrue([view lastEditorAction] == @selector(toggleBoldFormatting:));
    [view release];
}

- (void)testKeyDownEditorShortcutPreemptsVimHandler
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    [view setVimHandled:YES];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"="
                                                              modifiers:NSControlKeyMask];

    [view keyDown:event];

    XCTAssertFalse([view vimWasCalled]);
    XCTAssertTrue([view lastEditorAction] == @selector(increaseSourceEditorFontSize:));
    [view release];
}

- (void)testKeyDownRoutesNonShortcutInputToVimWhenHandled
{
    OMDSourceTextViewShortcutSpy *view = [self newShortcutSpyView];
    [view setVimHandled:YES];
    NSEvent *event = [self shortcutEventWithCharactersIgnoringModifiers:@"j"
                                                              modifiers:0];

    [view keyDown:event];

    XCTAssertTrue([view vimWasCalled]);
    XCTAssertTrue([view lastEditorAction] == NULL);
    [view release];
}

- (void)testSelectionStyleUsesTransparentBuiltInSelectionAttributes
{
    OMDSourceTextView *view = [self newSourceView];
    NSDictionary *selectionAttributes = [view selectedTextAttributes];
    NSColor *background = [selectionAttributes objectForKey:NSBackgroundColorAttributeName];
    NSColor *foreground = [selectionAttributes objectForKey:NSForegroundColorAttributeName];

    XCTAssertNotNil(background);
    XCTAssertEqualObjects(foreground, [NSColor clearColor]);
    [view release];
}

- (void)testSelectionDoesNotMutateStoredForegroundAttributes
{
    OMDSourceTextView *view = [self newSourceView];
    NSTextStorage *storage = [view textStorage];
    [storage setAttributedString:[[[NSAttributedString alloc] initWithString:@"alpha beta gamma"] autorelease]];
    NSColor *tokenColor = [NSColor colorWithCalibratedRed:0.70 green:0.20 blue:0.15 alpha:1.0];
    [storage addAttribute:NSForegroundColorAttributeName
                    value:tokenColor
                    range:NSMakeRange(0, [storage length])];

    [view setSelectedRange:NSMakeRange(1, 5)];

    NSColor *storedForeground = [storage attribute:NSForegroundColorAttributeName
                                           atIndex:2
                                    effectiveRange:NULL];
    XCTAssertEqualObjects(storedForeground, tokenColor);
    [view release];
}

@end
