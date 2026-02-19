// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDGitHubClient.h"

NSString * const OMDGitHubClientErrorDomain = @"OMDGitHubClientErrorDomain";
static NSString * const OMDGitHubTokenDefaultsKey = @"ObjcMarkdownGitHubToken";

static NSString *OMDExecutablePathNamed(NSString *name)
{
    if (name == nil || [name length] == 0) {
        return nil;
    }

    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *pathValue = [environment objectForKey:@"PATH"];
    if (pathValue == nil || [pathValue length] == 0) {
        return nil;
    }

    NSArray *searchPaths = [pathValue componentsSeparatedByString:@":"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *searchPath in searchPaths) {
        if (searchPath == nil || [searchPath length] == 0) {
            continue;
        }
        NSString *candidate = [searchPath stringByAppendingPathComponent:name];
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }

    return nil;
}

static NSString *OMDResolveCurlPath(void)
{
    NSString *pathValue = OMDExecutablePathNamed(@"curl");
    if (pathValue != nil) {
        return pathValue;
    }
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/curl"]) {
        return @"/usr/bin/curl";
    }
    return nil;
}

static NSString *OMDTrimmedString(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *OMDGitHubAccessToken(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults stringForKey:OMDGitHubTokenDefaultsKey];
    token = OMDTrimmedString(token);
    if ([token length] > 0) {
        return token;
    }

    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    token = OMDTrimmedString([environment objectForKey:@"OMD_GITHUB_TOKEN"]);
    if ([token length] > 0) {
        return token;
    }
    token = OMDTrimmedString([environment objectForKey:@"GITHUB_TOKEN"]);
    if ([token length] > 0) {
        return token;
    }
    return nil;
}

static NSString *OMDPercentEscapedString(NSString *value)
{
    if (value == nil) {
        return @"";
    }
    return [value stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

static NSString *OMDPercentEscapedPath(NSString *value)
{
    NSString *trimmed = OMDTrimmedString(value);
    if ([trimmed length] == 0) {
        return @"";
    }

    NSArray *components = [trimmed componentsSeparatedByString:@"/"];
    NSMutableArray *escaped = [NSMutableArray arrayWithCapacity:[components count]];
    for (NSString *component in components) {
        if ([component length] == 0) {
            continue;
        }
        [escaped addObject:OMDPercentEscapedString(component)];
    }
    return [escaped componentsJoinedByString:@"/"];
}

@interface OMDGitHubClient ()
- (NSError *)errorWithCode:(OMDGitHubClientErrorCode)code
               description:(NSString *)description
                    reason:(NSString *)reason
                statusCode:(NSInteger)statusCode;
- (BOOL)performRequestToURL:(NSString *)urlString
                 acceptJSON:(BOOL)acceptJSON
                   bodyData:(NSData **)bodyData
                 statusCode:(NSInteger *)statusCode
                      error:(NSError **)error;
- (id)JSONObjectFromData:(NSData *)data error:(NSError **)error;
- (NSError *)apiErrorForStatusCode:(NSInteger)statusCode data:(NSData *)data fallback:(NSString *)fallback;
@end

@implementation OMDGitHubClient

- (NSError *)errorWithCode:(OMDGitHubClientErrorCode)code
               description:(NSString *)description
                    reason:(NSString *)reason
                statusCode:(NSInteger)statusCode
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (description != nil) {
        [userInfo setObject:description forKey:NSLocalizedDescriptionKey];
    }
    if (reason != nil && [reason length] > 0) {
        [userInfo setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
    }
    if (statusCode > 0) {
        [userInfo setObject:[NSNumber numberWithInteger:statusCode] forKey:@"statusCode"];
    }
    return [NSError errorWithDomain:OMDGitHubClientErrorDomain code:code userInfo:userInfo];
}

- (BOOL)performRequestToURL:(NSString *)urlString
                 acceptJSON:(BOOL)acceptJSON
                   bodyData:(NSData **)bodyData
                 statusCode:(NSInteger *)statusCode
                      error:(NSError **)error
{
    NSString *curlPath = OMDResolveCurlPath();
    if (curlPath == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:OMDGitHubClientErrorCurlUnavailable
                             description:@"GitHub browsing requires curl."
                                  reason:@"Install curl to enable GitHub repository browsing."
                              statusCode:0];
        }
        return NO;
    }

    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory == nil || [temporaryDirectory length] == 0) {
        temporaryDirectory = @"/tmp";
    }
    NSString *outputPath = [temporaryDirectory stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"objcmarkdown-github-%@.tmp",
                                                       [[NSProcessInfo processInfo] globallyUniqueString]]];

    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:
                                 @"-sS",
                                 @"-L",
                                 @"--connect-timeout", @"8",
                                 @"--max-time", @"20",
                                 @"-H", @"User-Agent: MarkdownViewer",
                                 nil];
    if (acceptJSON) {
        [arguments addObjectsFromArray:[NSArray arrayWithObjects:@"-H",
                                                     @"Accept: application/vnd.github+json",
                                                     nil]];
    }
    NSString *token = OMDGitHubAccessToken();
    if (token != nil && [token length] > 0) {
        [arguments addObjectsFromArray:[NSArray arrayWithObjects:@"-H",
                                                     [NSString stringWithFormat:@"Authorization: Bearer %@", token],
                                                     nil]];
    }
    [arguments addObjectsFromArray:[NSArray arrayWithObjects:
                                    @"-o", outputPath,
                                    @"-w", @"%{http_code}",
                                    urlString,
                                    nil]];

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:curlPath];
    [task setArguments:arguments];

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    [task setStandardOutput:stdoutPipe];
    [task setStandardError:stderrPipe];

    BOOL launched = YES;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        launched = NO;
        if (error != NULL) {
            *error = [self errorWithCode:OMDGitHubClientErrorNetworkFailure
                             description:@"Unable to contact GitHub."
                                  reason:[exception reason]
                              statusCode:0];
        }
    }

    NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
    NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
    NSString *stdoutText = [[[NSString alloc] initWithData:stdoutData
                                                  encoding:NSUTF8StringEncoding] autorelease];
    NSString *stderrText = [[[NSString alloc] initWithData:stderrData
                                                  encoding:NSUTF8StringEncoding] autorelease];

    NSInteger parsedStatusCode = [OMDTrimmedString(stdoutText) integerValue];
    if (statusCode != NULL) {
        *statusCode = parsedStatusCode;
    }

    NSData *responseData = [NSData dataWithContentsOfFile:outputPath];
    [[NSFileManager defaultManager] removeItemAtPath:outputPath error:NULL];
    if (bodyData != NULL) {
        *bodyData = responseData;
    }

    if (!launched || [task terminationStatus] != 0) {
        if (error != NULL) {
            NSString *reason = OMDTrimmedString(stderrText);
            if ([reason length] == 0) {
                reason = @"curl exited with a non-zero status.";
            }
            *error = [self errorWithCode:OMDGitHubClientErrorNetworkFailure
                             description:@"Unable to contact GitHub."
                                  reason:reason
                              statusCode:parsedStatusCode];
        }
        return NO;
    }

    return YES;
}

- (id)JSONObjectFromData:(NSData *)data error:(NSError **)error
{
    if (data == nil || [data length] == 0) {
        if (error != NULL) {
            *error = [self errorWithCode:OMDGitHubClientErrorInvalidJSON
                             description:@"GitHub returned an empty response."
                                  reason:nil
                              statusCode:0];
        }
        return nil;
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (object == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:OMDGitHubClientErrorInvalidJSON
                             description:@"Unable to decode GitHub response."
                                  reason:[jsonError localizedDescription]
                              statusCode:0];
        }
        return nil;
    }
    return object;
}

- (NSError *)apiErrorForStatusCode:(NSInteger)statusCode data:(NSData *)data fallback:(NSString *)fallback
{
    NSString *message = nil;
    id object = [self JSONObjectFromData:data error:NULL];
    if ([object isKindOfClass:[NSDictionary class]]) {
        id messageValue = [object objectForKey:@"message"];
        if ([messageValue isKindOfClass:[NSString class]]) {
            message = messageValue;
        }
    }
    if (message == nil || [message length] == 0) {
        message = fallback;
    }

    OMDGitHubClientErrorCode code = OMDGitHubClientErrorHTTPFailure;
    if (statusCode == 404 && [fallback rangeOfString:@"user" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        code = OMDGitHubClientErrorUserNotFound;
    } else if (statusCode == 404 && [fallback rangeOfString:@"repository" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        code = OMDGitHubClientErrorRepositoryNotFound;
    } else if (statusCode == 403 &&
               [message rangeOfString:@"rate limit" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        code = OMDGitHubClientErrorRateLimited;
    }

    NSString *description = [NSString stringWithFormat:@"GitHub request failed (HTTP %ld).", (long)statusCode];
    if (code == OMDGitHubClientErrorRateLimited) {
        description = @"GitHub API rate limit reached.";
        message = [NSString stringWithFormat:@"%@\n\nSet a token in Preferences > Explorer > GitHub API Token, or OMD_GITHUB_TOKEN.",
                                     message != nil ? message : @"Rate limit exceeded."];
    } else if (code == OMDGitHubClientErrorUserNotFound) {
        description = @"GitHub user not found.";
    } else if (code == OMDGitHubClientErrorRepositoryNotFound) {
        description = @"GitHub repository not found.";
    }
    return [self errorWithCode:code description:description reason:message statusCode:statusCode];
}

- (NSArray *)publicRepositoriesForUser:(NSString *)user
               includeForksAndArchived:(BOOL)includeForksAndArchived
                                 error:(NSError **)error
{
    NSString *trimmedUser = OMDTrimmedString(user);
    if ([trimmedUser length] == 0) {
        return [NSArray array];
    }

    NSString *encodedUser = OMDPercentEscapedString(trimmedUser);
    NSString *urlString = [NSString stringWithFormat:
                           @"https://api.github.com/users/%@/repos?per_page=100&sort=updated&direction=desc&type=public",
                           encodedUser];
    NSData *bodyData = nil;
    NSInteger statusCode = 0;
    if (![self performRequestToURL:urlString
                        acceptJSON:YES
                          bodyData:&bodyData
                        statusCode:&statusCode
                             error:error]) {
        return nil;
    }

    if (statusCode >= 400) {
        if (error != NULL) {
            *error = [self apiErrorForStatusCode:statusCode
                                            data:bodyData
                                        fallback:@"Unable to load repositories for that user."];
        }
        return nil;
    }

    NSError *jsonError = nil;
    id object = [self JSONObjectFromData:bodyData error:&jsonError];
    if (object == nil || ![object isKindOfClass:[NSArray class]]) {
        if (error != NULL) {
            *error = (jsonError != nil
                      ? jsonError
                      : [self errorWithCode:OMDGitHubClientErrorInvalidJSON
                                 description:@"Unexpected GitHub repositories response."
                                      reason:nil
                                  statusCode:statusCode]);
        }
        return nil;
    }

    NSMutableArray *repos = [NSMutableArray array];
    for (id item in (NSArray *)object) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *repo = (NSDictionary *)item;
        NSString *name = [repo objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
            continue;
        }

        BOOL isFork = [[repo objectForKey:@"fork"] boolValue];
        BOOL isArchived = [[repo objectForKey:@"archived"] boolValue];
        if (!includeForksAndArchived && (isFork || isArchived)) {
            continue;
        }

        NSString *updatedAt = [repo objectForKey:@"updated_at"];
        if (![updatedAt isKindOfClass:[NSString class]]) {
            updatedAt = @"";
        }

        NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
        [normalized setObject:name forKey:@"name"];
        [normalized setObject:updatedAt forKey:@"updated_at"];
        [normalized setObject:[NSNumber numberWithBool:isFork] forKey:@"fork"];
        [normalized setObject:[NSNumber numberWithBool:isArchived] forKey:@"archived"];
        [repos addObject:normalized];
    }

    [repos sortUsingComparator:^NSComparisonResult(id left, id right) {
        NSString *leftUpdated = [left objectForKey:@"updated_at"];
        NSString *rightUpdated = [right objectForKey:@"updated_at"];
        NSComparisonResult updatedOrder = [rightUpdated compare:leftUpdated];
        if (updatedOrder != NSOrderedSame) {
            return updatedOrder;
        }
        NSString *leftName = [left objectForKey:@"name"];
        NSString *rightName = [right objectForKey:@"name"];
        return [leftName compare:rightName options:NSCaseInsensitiveSearch];
    }];

    return repos;
}

- (NSArray *)contentsForUser:(NSString *)user
                  repository:(NSString *)repository
                        path:(NSString *)path
                       error:(NSError **)error
{
    NSString *trimmedUser = OMDTrimmedString(user);
    NSString *trimmedRepository = OMDTrimmedString(repository);
    if ([trimmedUser length] == 0 || [trimmedRepository length] == 0) {
        return [NSArray array];
    }

    NSString *encodedUser = OMDPercentEscapedString(trimmedUser);
    NSString *encodedRepository = OMDPercentEscapedString(trimmedRepository);
    NSString *encodedPath = OMDPercentEscapedPath(path);

    NSString *urlString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/contents",
                           encodedUser,
                           encodedRepository];
    if ([encodedPath length] > 0) {
        urlString = [urlString stringByAppendingFormat:@"/%@", encodedPath];
    }

    NSData *bodyData = nil;
    NSInteger statusCode = 0;
    if (![self performRequestToURL:urlString
                        acceptJSON:YES
                          bodyData:&bodyData
                        statusCode:&statusCode
                             error:error]) {
        return nil;
    }

    if (statusCode >= 400) {
        if (error != NULL) {
            *error = [self apiErrorForStatusCode:statusCode
                                            data:bodyData
                                        fallback:@"Unable to load repository contents."];
        }
        return nil;
    }

    NSError *jsonError = nil;
    id object = [self JSONObjectFromData:bodyData error:&jsonError];
    if (object == nil) {
        if (error != NULL) {
            *error = jsonError;
        }
        return nil;
    }

    NSArray *items = nil;
    if ([object isKindOfClass:[NSArray class]]) {
        items = (NSArray *)object;
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        items = [NSArray arrayWithObject:object];
    } else {
        if (error != NULL) {
            *error = [self errorWithCode:OMDGitHubClientErrorInvalidJSON
                             description:@"Unexpected GitHub contents response."
                                  reason:nil
                              statusCode:statusCode];
        }
        return nil;
    }

    NSMutableArray *entries = [NSMutableArray array];
    for (id item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *entry = (NSDictionary *)item;
        NSString *name = [entry objectForKey:@"name"];
        NSString *entryPath = [entry objectForKey:@"path"];
        NSString *type = [entry objectForKey:@"type"];
        if (![name isKindOfClass:[NSString class]] ||
            ![entryPath isKindOfClass:[NSString class]] ||
            ![type isKindOfClass:[NSString class]]) {
            continue;
        }

        NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
        [normalized setObject:name forKey:@"name"];
        [normalized setObject:entryPath forKey:@"path"];
        [normalized setObject:type forKey:@"type"];

        id size = [entry objectForKey:@"size"];
        if ([size respondsToSelector:@selector(unsignedLongLongValue)]) {
            [normalized setObject:[NSNumber numberWithUnsignedLongLong:[size unsignedLongLongValue]]
                           forKey:@"size"];
        }

        id downloadURL = [entry objectForKey:@"download_url"];
        if ([downloadURL isKindOfClass:[NSString class]] && [downloadURL length] > 0) {
            [normalized setObject:downloadURL forKey:@"download_url"];
        }
        [entries addObject:normalized];
    }

    [entries sortUsingComparator:^NSComparisonResult(id left, id right) {
        NSString *leftType = [left objectForKey:@"type"];
        NSString *rightType = [right objectForKey:@"type"];
        BOOL leftDir = [leftType isEqualToString:@"dir"];
        BOOL rightDir = [rightType isEqualToString:@"dir"];
        if (leftDir != rightDir) {
            return leftDir ? NSOrderedAscending : NSOrderedDescending;
        }
        NSString *leftName = [left objectForKey:@"name"];
        NSString *rightName = [right objectForKey:@"name"];
        return [leftName compare:rightName options:NSCaseInsensitiveSearch];
    }];

    return entries;
}

- (NSData *)downloadDataFromURLString:(NSString *)urlString
                                error:(NSError **)error
{
    NSString *trimmed = OMDTrimmedString(urlString);
    if ([trimmed length] == 0) {
        if (error != NULL) {
            *error = [self errorWithCode:OMDGitHubClientErrorNetworkFailure
                             description:@"Invalid download URL."
                                  reason:nil
                              statusCode:0];
        }
        return nil;
    }

    NSData *bodyData = nil;
    NSInteger statusCode = 0;
    if (![self performRequestToURL:trimmed
                        acceptJSON:NO
                          bodyData:&bodyData
                        statusCode:&statusCode
                             error:error]) {
        return nil;
    }

    if (statusCode >= 400) {
        if (error != NULL) {
            *error = [self errorWithCode:OMDGitHubClientErrorHTTPFailure
                             description:[NSString stringWithFormat:@"Download failed (HTTP %ld).", (long)statusCode]
                                  reason:@"GitHub could not provide the requested file."
                              statusCode:statusCode];
        }
        return nil;
    }

    return bodyData;
}

@end
