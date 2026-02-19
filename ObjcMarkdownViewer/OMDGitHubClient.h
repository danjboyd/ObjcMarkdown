// ObjcMarkdownViewer
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>

extern NSString * const OMDGitHubClientErrorDomain;

typedef NS_ENUM(NSInteger, OMDGitHubClientErrorCode) {
    OMDGitHubClientErrorCurlUnavailable = 1,
    OMDGitHubClientErrorNetworkFailure = 2,
    OMDGitHubClientErrorHTTPFailure = 3,
    OMDGitHubClientErrorInvalidJSON = 4,
    OMDGitHubClientErrorUserNotFound = 5,
    OMDGitHubClientErrorRepositoryNotFound = 6,
    OMDGitHubClientErrorRateLimited = 7
};

@interface OMDGitHubClient : NSObject

- (NSArray *)publicRepositoriesForUser:(NSString *)user
               includeForksAndArchived:(BOOL)includeForksAndArchived
                                 error:(NSError **)error;
- (NSArray *)contentsForUser:(NSString *)user
                  repository:(NSString *)repository
                        path:(NSString *)path
                       error:(NSError **)error;
- (NSData *)downloadDataFromURLString:(NSString *)urlString
                                error:(NSError **)error;

@end
