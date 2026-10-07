// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDRemoteDocument.h"
#import "OMDExternalTools.h"
#import "OMDTextFileSupport.h"
#import "OMDMainThread.h"

static NSString *OMDEscapedPathComponents(NSArray *components)
{
    NSMutableArray *escaped = [NSMutableArray arrayWithCapacity:[components count]];
    NSCharacterSet *allowed = [NSCharacterSet URLPathAllowedCharacterSet];
    for (NSString *component in components) {
        NSString *part = [component stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        // "/" is allowed in a path but not inside one of its components.
        part = [part stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
        [escaped addObject:(part != nil ? part : component)];
    }
    return [escaped componentsJoinedByString:@"/"];
}

// The URL's path components, decoded, without the leading "/", with "."
// and ".." resolved (GNUstep's NSURL keeps them in a relative link it
// resolves, and servers answer them with redirects).
static NSArray *OMDPathComponents(NSURL *url)
{
    NSMutableArray *components = [NSMutableArray array];
    for (NSString *component in [[url path] pathComponents]) {
        if ([component length] == 0 || [component isEqualToString:@"/"] || [component isEqualToString:@"."]) {
            continue;
        }
        if ([component isEqualToString:@".."]) {
            if ([components count] > 0) {
                [components removeLastObject];
            }
            continue;
        }
        [components addObject:component];
    }
    return components;
}

static BOOL OMDIsMarkdownName(NSString *name)
{
    return OMDIsMarkdownExtension([[name pathExtension] lowercaseString]);
}

@implementation OMDRemoteDocument

- (void)dealloc
{
    [_rawURL release];
    [_pageURL release];
    [_fileName release];
    [_owner release];
    [_repository release];
    [_ref release];
    [super dealloc];
}

+ (instancetype)documentWithURLString:(NSString *)string
{
    NSString *trimmed = OMDTrimmedString(string);
    if ([trimmed length] == 0) {
        return nil;
    }
    NSString *lower = [trimmed lowercaseString];
    if ([lower hasPrefix:@"github.com/"] || [lower hasPrefix:@"www.github.com/"] ||
        [lower hasPrefix:@"raw.githubusercontent.com/"]) {
        trimmed = [@"https://" stringByAppendingString:trimmed];
    }
    NSURL *url = [NSURL URLWithString:trimmed];
    NSString *scheme = [[url scheme] lowercaseString];
    if (url == nil || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) ||
        [[url host] length] == 0) {
        return nil;
    }

    NSString *host = [[url host] lowercaseString];
    NSArray *components = OMDPathComponents(url);
    OMDRemoteDocument *document = [[[OMDRemoteDocument alloc] init] autorelease];

    if ([host isEqualToString:@"github.com"] || [host isEqualToString:@"www.github.com"]) {
        // OWNER/REPO/blob|raw/REF/PATH...
        if ([components count] < 5) {
            return nil;
        }
        NSString *kind = [components objectAtIndex:2];
        if (!([kind isEqualToString:@"blob"] || [kind isEqualToString:@"raw"])) {
            return nil;
        }
        if (!OMDIsMarkdownName([components lastObject])) {
            return nil;
        }
        NSString *owner = [components objectAtIndex:0];
        NSString *repository = [components objectAtIndex:1];
        NSArray *rest = [components subarrayWithRange:NSMakeRange(3, [components count] - 3)];
        NSString *escapedRest = OMDEscapedPathComponents(rest);
        NSString *base = OMDEscapedPathComponents([NSArray arrayWithObjects:owner, repository, nil]);
        document->_rawURL = [[NSURL URLWithString:[NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@",
                                                                             base, escapedRest]] retain];
        document->_pageURL = [[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@/blob/%@",
                                                                              base, escapedRest]] retain];
        document->_owner = [owner copy];
        document->_repository = [repository copy];
        document->_ref = [[rest objectAtIndex:0] copy];
    } else if ([host isEqualToString:@"raw.githubusercontent.com"]) {
        // OWNER/REPO/REF/PATH..., where REF may be refs/heads/NAME.
        if ([components count] < 4 || !OMDIsMarkdownName([components lastObject])) {
            return nil;
        }
        NSString *owner = [components objectAtIndex:0];
        NSString *repository = [components objectAtIndex:1];
        NSArray *rest = [components subarrayWithRange:NSMakeRange(2, [components count] - 2)];
        NSString *ref = [rest objectAtIndex:0];
        NSArray *pageRest = rest;
        if ([ref isEqualToString:@"refs"] && [rest count] >= 4 &&
            ([[rest objectAtIndex:1] isEqualToString:@"heads"] || [[rest objectAtIndex:1] isEqualToString:@"tags"])) {
            ref = [rest objectAtIndex:2];
            pageRest = [rest subarrayWithRange:NSMakeRange(2, [rest count] - 2)];
        }
        NSString *base = OMDEscapedPathComponents([NSArray arrayWithObjects:owner, repository, nil]);
        document->_rawURL = [[NSURL URLWithString:[NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@",
                                                                             base, OMDEscapedPathComponents(rest)]] retain];
        document->_pageURL = [[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@/blob/%@",
                                                                              base, OMDEscapedPathComponents(pageRest)]] retain];
        document->_owner = [owner copy];
        document->_repository = [repository copy];
        document->_ref = [ref copy];
    } else {
        if ([components count] == 0 || !OMDIsMarkdownName([components lastObject])) {
            return nil;
        }
        // Without the fragment; the query may be part of the address.
        NSString *query = [url query];
        NSString *absolute = [NSString stringWithFormat:@"%@://%@%@/%@%@",
                                                        scheme,
                                                        [url host],
                                                        ([url port] != nil ? [NSString stringWithFormat:@":%@", [url port]] : @""),
                                                        OMDEscapedPathComponents(components),
                                                        ([query length] > 0 ? [@"?" stringByAppendingString:query] : @"")];
        document->_rawURL = [[NSURL URLWithString:absolute] retain];
        document->_pageURL = [document->_rawURL retain];
    }
    if (document->_rawURL == nil || document->_pageURL == nil) {
        return nil;
    }
    document->_fileName = [[components lastObject] copy];
    return document;
}

- (NSURL *)rawURL
{
    return _rawURL;
}

- (NSURL *)pageURL
{
    return _pageURL;
}

- (NSURL *)baseURL
{
    // Up to the last "/" of the path (GNUstep's NSURL keeps "./" in
    // [NSURL URLWithString:@"./" relativeToURL:]).
    NSString *address = [_rawURL absoluteString];
    NSRange query = [address rangeOfString:@"?"];
    if (query.location != NSNotFound) {
        address = [address substringToIndex:query.location];
    }
    NSRange slash = [address rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location == NSNotFound) {
        return _rawURL;
    }
    return [NSURL URLWithString:[address substringToIndex:NSMaxRange(slash)]];
}

- (NSString *)fileName
{
    return _fileName;
}

- (NSString *)owner
{
    return _owner;
}

- (NSString *)repository
{
    return _repository;
}

- (NSString *)ref
{
    return _ref;
}

- (BOOL)isOnGitHub
{
    return _owner != nil;
}

- (NSString *)summary
{
    if ([self isOnGitHub]) {
        return [NSString stringWithFormat:@"%@/%@ · %@", _owner, _repository, _ref];
    }
    return [_rawURL host];
}

@end

static NSString *OMDGitHubToken(void)
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    for (NSString *name in [NSArray arrayWithObjects:@"OMD_GITHUB_TOKEN", @"GITHUB_TOKEN", nil]) {
        NSString *token = OMDTrimmedString([environment objectForKey:name]);
        if ([token length] > 0) {
            return token;
        }
    }
    return nil;
}

static NSString *OMDFetchErrorMessage(NSInteger status, NSString *failure, OMDRemoteDocument *document)
{
    if (status == 404) {
        return ([document isOnGitHub]
                ? @"Not found. (A private repository needs GITHUB_TOKEN set.)"
                : @"Not found (404).");
    }
    if (status == 401 || status == 403) {
        return @"Not allowed. (A private repository needs GITHUB_TOKEN set.)";
    }
    if (status == 429) {
        return @"Too many requests; try again later.";
    }
    if (status >= 400) {
        return [NSString stringWithFormat:@"The server answered %ld.", (long)status];
    }
    return ([failure length] > 0 ? [NSString stringWithFormat:@"Couldn't fetch it: %@.", failure]
                                 : @"Couldn't fetch it. Check the connection.");
}

// Fetches url with curl, which follows redirects (GNUstep's synchronous
// NSURLConnection hangs on them). The token goes in through curl's standard
// input, not its command line. NO when curl isn't there or couldn't run.
static BOOL OMDFetchWithCurl(NSURL *url, NSString *token, NSUInteger maxBytes,
                             NSData **dataOut, NSInteger *statusOut, NSString **failureOut)
{
    NSString *curl = OMDExecutablePathNamed(@"curl");
    if (curl == nil) {
        return NO;
    }
    NSString *bodyPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"omd-remote-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSMutableString *config = [NSMutableString stringWithString:@"header = \"User-Agent: MarkdownViewer\"\n"];
    if (token != nil) {
        [config appendFormat:@"header = \"Authorization: Bearer %@\"\n", token];
    }
    NSArray *arguments = [NSArray arrayWithObjects:@"--silent", @"--show-error", @"--location",
                          @"--max-redirs", @"5", @"--max-time", @"30",
                          @"--max-filesize", [NSString stringWithFormat:@"%lu", (unsigned long)(maxBytes + 1)],
                          @"--config", @"-",
                          @"--output", bodyPath,
                          @"--write-out", @"%{http_code}",
                          [url absoluteString], nil];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    NSPipe *input = [NSPipe pipe];
    NSPipe *output = [NSPipe pipe];
    NSPipe *errors = [NSPipe pipe];
    [task setLaunchPath:curl];
    [task setArguments:arguments];
    [task setStandardInput:input];
    [task setStandardOutput:output];
    [task setStandardError:errors];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        return NO;
    }
    [[input fileHandleForWriting] writeData:[config dataUsingEncoding:NSUTF8StringEncoding]];
    [[input fileHandleForWriting] closeFile];
    NSData *statusData = [[output fileHandleForReading] readDataToEndOfFile];
    NSData *errorData = [[errors fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];

    NSString *statusText = [[[NSString alloc] initWithData:statusData encoding:NSUTF8StringEncoding] autorelease];
    *statusOut = [OMDTrimmedString(statusText) integerValue];
    *dataOut = [NSData dataWithContentsOfFile:bodyPath];
    [[NSFileManager defaultManager] removeItemAtPath:bodyPath error:NULL];
    if ([task terminationStatus] == 63) {
        // --max-filesize: more than maxBytes.
        *dataOut = nil;
        *failureOut = @"too large";
    } else if ([task terminationStatus] != 0) {
        *dataOut = nil;
        NSString *reason = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] autorelease];
        reason = OMDTrimmedString(reason);
        if ([reason hasPrefix:@"curl: "]) {
            reason = [reason substringFromIndex:6];
        }
        *failureOut = ([reason length] > 0 ? reason : @"the connection failed");
    }
    return YES;
}

void OMDFetchRemoteDocument(OMDRemoteDocument *document,
                            NSUInteger maxBytes,
                            void (^completion)(NSString *markdown, NSString *errorMessage))
{
    NSURL *url = [[document rawURL] retain];
    BOOL sendToken = [document isOnGitHub];
    [document retain];
    void (^callback)(NSString *, NSString *) = [completion copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *token = (sendToken ? OMDGitHubToken() : nil);
        NSData *data = nil;
        NSInteger status = 0;
        NSString *failure = nil;
        if (!OMDFetchWithCurl(url, token, maxBytes, &data, &status, &failure)) {
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                               timeoutInterval:20.0];
            [request setValue:@"MarkdownViewer" forHTTPHeaderField:@"User-Agent"];
            if (token != nil) {
                [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
            }
            NSURLResponse *response = nil;
            NSError *error = nil;
            data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            status = ([response respondsToSelector:@selector(statusCode)]
                      ? [(NSHTTPURLResponse *)response statusCode] : 0);
            failure = [error localizedDescription];
        }

        NSString *markdown = nil;
        NSString *message = nil;
        if ([failure isEqualToString:@"too large"] || [data length] > maxBytes) {
            message = [NSString stringWithFormat:@"It is larger than the %lu MB limit in Preferences.",
                                                 (unsigned long)(maxBytes / (1024 * 1024))];
        } else if (data == nil || status >= 400) {
            message = OMDFetchErrorMessage(status, failure, document);
        } else if (OMDDataAppearsBinary(data)) {
            message = @"It isn't text.";
        } else {
            markdown = OMDDecodeTextFromData(data, NULL);
            if (markdown == nil) {
                message = @"Its text couldn't be read.";
            }
        }
        [markdown retain];
        [message retain];
        OMDPerformOnMainThread(^{
            callback(markdown, message);
            [markdown release];
            [message release];
            [callback release];
            [document release];
            [url release];
        });
        [pool release];
    });
}
