// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// A Markdown document on the web, which the viewer opens read-only: a file
// on GitHub (its page, github.com/OWNER/REPO/blob/REF/PATH, or its raw
// address on raw.githubusercontent.com) or any http(s) address of a .md
// file.
@interface OMDRemoteDocument : NSObject
{
    NSURL *_rawURL;
    NSURL *_pageURL;
    NSString *_fileName;
    NSString *_owner;
    NSString *_repository;
    NSString *_ref;
}

// nil when the address isn't one of those. "github.com/..." without a
// scheme is taken as https.
+ (instancetype)documentWithURLString:(NSString *)string;

// What is fetched: the file's own content.
- (NSURL *)rawURL;
// What a browser shows: the GitHub page for a GitHub file, else rawURL.
- (NSURL *)pageURL;
// The folder relative links and images resolve against.
- (NSURL *)baseURL;
- (NSString *)fileName;
// For a GitHub file; nil otherwise. A ref with a slash in it can't be told
// from the path in a URL, so ref is the first part (the address itself is
// the same either way).
- (NSString *)owner;
- (NSString *)repository;
- (NSString *)ref;
- (BOOL)isOnGitHub;
// "owner/repo · ref" for a GitHub file, else the host.
- (NSString *)summary;

@end

// Fetches the document on a background queue and calls back on the main
// thread with its text, or nil and a message saying what went wrong. A
// GitHub token from OMD_GITHUB_TOKEN or GITHUB_TOKEN is sent to GitHub's
// hosts (private repositories). Larger than maxBytes is an error.
void OMDFetchRemoteDocument(OMDRemoteDocument *document,
                            NSUInteger maxBytes,
                            void (^completion)(NSString *markdown, NSString *errorMessage));
