// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDShareMail.h"

NSURL *OMDMailtoURLWithSubject(NSString *subject)
{
    NSMutableCharacterSet *allowed = [[[NSCharacterSet alphanumericCharacterSet] mutableCopy] autorelease];
    [allowed addCharactersInString:@"-._~"];
    NSString *encoded = [(subject != nil ? subject : @"") stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return [NSURL URLWithString:[NSString stringWithFormat:@"mailto:?subject=%@", (encoded != nil ? encoded : @"")]];
}

BOOL OMDMailAppTakesAttachments(NSString *appID)
{
    NSString *lower = [appID lowercaseString];
    if ([lower length] == 0) {
        return NO;
    }
    NSArray *clients = [NSArray arrayWithObjects:@"evolution", @"thunderbird", @"betterbird",
                                                 @"kmail", @"claws-mail", @"sylpheed", nil];
    for (NSString *client in clients) {
        if ([lower rangeOfString:client].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}
