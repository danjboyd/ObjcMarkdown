// ObjcMarkdownTests
// SPDX-License-Identifier: GPL-2.0-or-later

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "OMDShareMail.h"

@interface OMDShareMailTests : XCTestCase
@end

@implementation OMDShareMailTests

- (void)testMailtoSubjectIsPercentEncoded
{
    XCTAssertEqualObjects([OMDMailtoURLWithSubject(@"Q3 Plan & notes") absoluteString],
                          @"mailto:?subject=Q3%20Plan%20%26%20notes");
    XCTAssertEqualObjects([OMDMailtoURLWithSubject(@"a-b_c.d~e") absoluteString],
                          @"mailto:?subject=a-b_c.d~e");
    XCTAssertEqualObjects([OMDMailtoURLWithSubject(nil) absoluteString], @"mailto:?subject=");
}

- (void)testDesktopMailClientsTakeAttachments
{
    XCTAssertTrue(OMDMailAppTakesAttachments(@"org.gnome.Evolution.desktop"));
    XCTAssertTrue(OMDMailAppTakesAttachments(@"thunderbird.desktop"));
    XCTAssertTrue(OMDMailAppTakesAttachments(@"net.thunderbird.Thunderbird.desktop"));
    XCTAssertTrue(OMDMailAppTakesAttachments(@"org.kde.kmail2.desktop"));
    XCTAssertTrue(OMDMailAppTakesAttachments(@"claws-mail.desktop"));
}

- (void)testBrowsersAndUnknownAppsDont
{
    XCTAssertFalse(OMDMailAppTakesAttachments(@"vivaldi-stable.desktop"));
    XCTAssertFalse(OMDMailAppTakesAttachments(@"firefox-esr.desktop"));
    XCTAssertFalse(OMDMailAppTakesAttachments(@"org.gnome.Geary.desktop"));
    XCTAssertFalse(OMDMailAppTakesAttachments(@""));
    XCTAssertFalse(OMDMailAppTakesAttachments(nil));
}

- (void)testThunderbirdIsRecognised
{
    XCTAssertTrue(OMDMailAppIsThunderbird(@"thunderbird.desktop"));
    XCTAssertTrue(OMDMailAppIsThunderbird(@"net.thunderbird.Thunderbird.desktop"));
    XCTAssertTrue(OMDMailAppIsThunderbird(@"eu.betterbird.Betterbird.desktop"));
    XCTAssertFalse(OMDMailAppIsThunderbird(@"org.gnome.Evolution.desktop"));
    XCTAssertFalse(OMDMailAppIsThunderbird(nil));
}

- (void)testThunderbirdComposeArgument
{
    XCTAssertEqualObjects(OMDThunderbirdComposeArgument(@"Q3 Plan", @"/tmp/x/Q3 Plan.html"),
                          @"subject='Q3 Plan',message='/tmp/x/Q3 Plan.html',format=html");
    XCTAssertEqualObjects(OMDThunderbirdComposeArgument(@"Dan's plan, v2", @"/tmp/a.html"),
                          @"subject='Dans plan v2',message='/tmp/a.html',format=html");
    XCTAssertNil(OMDThunderbirdComposeArgument(@"x", @"/tmp/it's.html"));
    XCTAssertNil(OMDThunderbirdComposeArgument(@"x", nil));
}

@end
