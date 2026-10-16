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

BOOL OMDMailAppIsThunderbird(NSString *appID)
{
    NSString *lower = [appID lowercaseString];
    if ([lower length] == 0) {
        return NO;
    }
    return [lower rangeOfString:@"thunderbird"].location != NSNotFound ||
           [lower rangeOfString:@"betterbird"].location != NSNotFound;
}

NSString *OMDThunderbirdComposeArgument(NSString *subject, NSString *path)
{
    if ([path length] == 0 || [path rangeOfString:@"'"].location != NSNotFound) {
        return nil;
    }
    NSMutableString *clean = [NSMutableString stringWithString:(subject != nil ? subject : @"")];
    [clean replaceOccurrencesOfString:@"'" withString:@"" options:0 range:NSMakeRange(0, [clean length])];
    [clean replaceOccurrencesOfString:@"," withString:@"" options:0 range:NSMakeRange(0, [clean length])];
    return [NSString stringWithFormat:@"subject='%@',message='%@',format=html", clean, path];
}
