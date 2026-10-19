/* GSSharingRclone.m: uploads a file with rclone and makes a link to it.

   Copyright (C) 2026 Daniel Boyd

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   Foundation only, manual retain and release, no blocks (GCC): the work
   runs on a thread of its own and tells the delegate on the main thread. */

#import "GSSharingRclone.h"

#if defined(_WIN32)
#  include <windows.h>
#endif

NSString * const GSSharingRcloneErrorDomain = @"GSSharingRcloneErrorDomain";
NSString * const GSSharingRcloneRemotesDidChangeNotification
  = @"GSSharingRcloneRemotesDidChangeNotification";

/* How long a look at the remotes is kept, and how long rclone may take to
   list them or to make a link. */
static const NSTimeInterval GSSharingRcloneCacheSeconds = 60.0;
static const NSTimeInterval GSSharingRcloneListTimeout = 20.0;
static const NSTimeInterval GSSharingRcloneLinkTimeout = 60.0;
static const NSTimeInterval GSSharingRcloneDeleteTimeout = 30.0;

/* The backends that make links, with a name for people. */
static NSDictionary *
GSSharingRcloneBackendNames(void)
{
  static NSDictionary *names = nil;

  if (names == nil)
    {
      names = [[NSDictionary alloc] initWithObjectsAndKeys:
        @"OneDrive", @"onedrive",
        @"Google Drive", @"drive",
        @"Dropbox", @"dropbox",
        @"Box", @"box",
        @"pCloud", @"pcloud",
        @"MEGA", @"mega",
        @"Jottacloud", @"jottacloud",
        @"Koofr", @"koofr",
        @"Seafile", @"seafile",
        @"Zoho WorkDrive", @"zoho",
        @"ShareFile", @"sharefile",
        @"Enterprise File Fabric", @"filefabric",
        @"OpenDrive", @"opendrive",
        @"premiumize.me", @"premiumizeme",
        @"put.io", @"putio",
        nil];
    }
  return names;
}

static NSError *
GSSharingRcloneError(NSInteger code, NSString *description, NSString *reason)
{
  NSMutableDictionary *info = [NSMutableDictionary dictionary];

  [info setObject: description forKey: NSLocalizedDescriptionKey];
  if ([reason length] > 0)
    {
      [info setObject: reason forKey: NSLocalizedFailureReasonErrorKey];
    }
  return [NSError errorWithDomain: GSSharingRcloneErrorDomain
                             code: code
                         userInfo: info];
}

/* The app's name for people: what the bundle says, then the process. */
static NSString *
GSSharingRcloneAppName(void)
{
  NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
  NSString *name = [info objectForKey: @"CFBundleDisplayName"];

  if ([name isKindOfClass: [NSString class]] == NO || [name length] == 0)
    {
      name = [info objectForKey: @"CFBundleName"];
    }
  if ([name isKindOfClass: [NSString class]] == NO || [name length] == 0)
    {
      name = [[NSProcessInfo processInfo] processName];
    }
  return name;
}


@implementation GSSharingRcloneRemote

- (id) initWithName: (NSString *)name type: (NSString *)type
{
  if ((self = [super init]) != nil)
    {
      _name = [name copy];
      _type = [type copy];
    }
  return self;
}

- (void) dealloc
{
  [_name release];
  [_type release];
  [super dealloc];
}

- (NSString *) name
{
  return _name;
}

- (NSString *) type
{
  return _type;
}

- (NSString *) displayName
{
  NSString *backend = [GSSharingRcloneBackendNames() objectForKey: _type];

  if (backend == nil)
    {
      return _name;
    }
  return [NSString stringWithFormat: @"%@ (%@)", _name, backend];
}

- (NSArray *) linkArguments
{
  if ([_type isEqualToString: @"onedrive"])
    {
      return [NSArray arrayWithObjects:
        @"--onedrive-link-scope", @"organization",
        @"--onedrive-link-type", @"view", nil];
    }
  return [NSArray array];
}

- (NSString *) audience
{
  if ([_type isEqualToString: @"onedrive"])
    {
      return @"People in your organization who have the link can open it.";
    }
  return @"Anyone with the link can open it.";
}

- (NSString *) description
{
  return [NSString stringWithFormat: @"<%@ %@: %@>",
                   NSStringFromClass([self class]), _name, _type];
}

@end


/* Runs rclone with args and waits, at most timeout seconds (0: no limit).
   The output goes to *output (stdout) and *errors (stderr). Returns the
   exit status, or -1 if it couldn't run or was stopped. The task is kept
   in *running while it runs (under lock), so another thread can stop it. */
static int
GSSharingRcloneRun(NSArray *args, NSString *password, NSTimeInterval timeout,
                   NSString **output, NSString **errors,
                   NSTask **running, NSLock *lock)
{
  NSString *path = [GSSharingRclone executablePath];
  NSTask *task;
  NSPipe *outPipe;
  NSPipe *errPipe;
  NSMutableDictionary *environment;
  NSData *outData;
  NSData *errData;
  NSDate *deadline;
  int status = -1;

  if (output != NULL)
    {
      *output = nil;
    }
  if (errors != NULL)
    {
      *errors = nil;
    }
  if (path == nil)
    {
      return -1;
    }
  task = [[NSTask alloc] init];
  outPipe = [NSPipe pipe];
  errPipe = [NSPipe pipe];
  environment = [NSMutableDictionary dictionaryWithDictionary:
    [[NSProcessInfo processInfo] environment]];
  /* An encrypted config fails instead of asking on a terminal nobody sees;
     its password, when given, is for this run only. */
  [environment setObject: @"false" forKey: @"RCLONE_ASK_PASSWORD"];
  [environment removeObjectForKey: @"RCLONE_CONFIG_PASS"];
  if ([password length] > 0)
    {
      [environment setObject: password forKey: @"RCLONE_CONFIG_PASS"];
    }
  [task setLaunchPath: path];
  [task setArguments: args];
  [task setEnvironment: environment];
  [task setStandardInput: [NSFileHandle fileHandleWithNullDevice]];
  [task setStandardOutput: outPipe];
  [task setStandardError: errPipe];
  NS_DURING
    {
      [task launch];
    }
  NS_HANDLER
    {
      [task release];
      task = nil;
    }
  NS_ENDHANDLER
  if (task == nil)
    {
      return -1;
    }
  if (running != NULL)
    {
      [lock lock];
      *running = task;
      [lock unlock];
    }
  /* The output is small for everything but the upload, which reads its
     own: wait for the end, stopping rclone when the time is up. */
  deadline = timeout > 0 ? [NSDate dateWithTimeIntervalSinceNow: timeout] : nil;
  while ([task isRunning])
    {
      if (deadline != nil && [deadline timeIntervalSinceNow] < 0)
        {
          [task terminate];
          break;
        }
      [NSThread sleepForTimeInterval: 0.05];
    }
  outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
  errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
  [task waitUntilExit];
  if (running != NULL)
    {
      [lock lock];
      *running = nil;
      [lock unlock];
    }
  if (deadline == nil || [deadline timeIntervalSinceNow] >= 0)
    {
      status = [task terminationStatus];
    }
  if (output != NULL)
    {
      *output = [[[NSString alloc] initWithData: outData
                                       encoding: NSUTF8StringEncoding] autorelease];
    }
  if (errors != NULL)
    {
      *errors = [[[NSString alloc] initWithData: errData
                                       encoding: NSUTF8StringEncoding] autorelease];
    }
  [task release];
  return status;
}

/* rclone's last line that says what went wrong, without its time stamp, or
   the whole text if no line does. */
static NSString *
GSSharingRcloneLastError(NSString *text)
{
  NSArray *lines = [text componentsSeparatedByString: @"\n"];
  NSEnumerator *e = [lines reverseObjectEnumerator];
  NSString *line;

  while ((line = [e nextObject]) != nil)
    {
      NSRange level = [line rangeOfString: @"ERROR : "];

      if (level.location == NSNotFound)
        {
          level = [line rangeOfString: @"CRITICAL: "];
        }
      if (level.location == NSNotFound)
        {
          level = [line rangeOfString: @"NOTICE: Failed"];
          if (level.location != NSNotFound)
            {
              level.length = 8;   /* keep "Failed" */
            }
        }
      if (level.location == NSNotFound)
        {
          level = [line rangeOfString: @"Failed to "];
          if (level.location != NSNotFound)
            {
              level.length = 0;
            }
        }
      if (level.location != NSNotFound)
        {
          return [[line substringFromIndex: NSMaxRange(level)]
                   stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
  return [text stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}


@interface GSSharingRclone (Private)
+ (NSArray *) fetchRemotesWithPassword: (NSString *)password error: (NSError **)error;
@end

@implementation GSSharingRclone

static NSArray *cachedRemotes = nil;
static NSDate *cachedAt = nil;
static NSError *lastError = nil;
static BOOL refreshing = NO;
static BOOL refreshAgain = NO;
static NSString *refreshPassword = nil;
static NSLock *cacheLock = nil;
static NSString *chosenExecutable = nil;

+ (void) initialize
{
  if (self == [GSSharingRclone class] && cacheLock == nil)
    {
      cacheLock = [[NSLock alloc] init];
    }
}

+ (void) setExecutablePath: (NSString *)path
{
  NSString *copy = [path copy];

  [cacheLock lock];
  [chosenExecutable release];
  chosenExecutable = copy;
  [cacheLock unlock];
  [self forgetRemotes];
}

/* An environment variable. Windows' names ignore case, and its PATH is
   "Path", but GNUstep's environment dictionary is case-sensitive. */
static NSString *
GSSharingRcloneEnvironmentValue(NSDictionary *environment, NSString *name)
{
  NSString *value = [environment objectForKey: name];
#if defined(_WIN32)
  NSEnumerator *e;
  NSString *key;

  if (value != nil)
    {
      return value;
    }
  e = [environment keyEnumerator];
  while ((key = [e nextObject]) != nil)
    {
      if ([key caseInsensitiveCompare: name] == NSOrderedSame)
        {
          return [environment objectForKey: key];
        }
    }
#endif
  return value;
}

+ (NSString *) executablePath
{
  NSFileManager *manager = [NSFileManager defaultManager];
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *home = NSHomeDirectory();
  NSMutableArray *directories = [NSMutableArray array];
  NSString *pathList = GSSharingRcloneEnvironmentValue(environment, @"PATH");
  NSEnumerator *e;
  NSString *directory;
#if defined(_WIN32)
  NSString *name = @"rclone.exe";
  NSString *separator = @";";
  NSString *local = GSSharingRcloneEnvironmentValue(environment, @"LOCALAPPDATA");
  NSString *programData = GSSharingRcloneEnvironmentValue(environment, @"ProgramData");
#else
  NSString *name = @"rclone";
  NSString *separator = @":";
#endif
  NSString *chosen;

  [cacheLock lock];
  chosen = [[chosenExecutable retain] autorelease];
  [cacheLock unlock];
  if (chosen != nil)
    {
      return [manager isExecutableFileAtPath: chosen] ? chosen : nil;
    }
  if ([pathList length] > 0)
    {
      [directories addObjectsFromArray:
        [pathList componentsSeparatedByString: separator]];
    }
#if defined(_WIN32)
  if ([local length] > 0)
    {
      [directories addObject: [local stringByAppendingPathComponent:
                                 @"Microsoft/WinGet/Links"]];
    }
  if ([programData length] > 0)
    {
      [directories addObject: [programData stringByAppendingPathComponent:
                                 @"chocolatey/bin"]];
    }
  [directories addObject: [home stringByAppendingPathComponent: @"scoop/shims"]];
#else
  [directories addObject: @"/usr/local/bin"];
  [directories addObject: @"/opt/homebrew/bin"];
  [directories addObject: @"/opt/local/bin"];
  [directories addObject: @"/usr/bin"];
  [directories addObject: [home stringByAppendingPathComponent: @".local/bin"]];
  [directories addObject: [home stringByAppendingPathComponent: @"bin"]];
#endif
  e = [directories objectEnumerator];
  while ((directory = [e nextObject]) != nil)
    {
      NSString *candidate;

      if ([directory length] == 0)
        {
          continue;
        }
      candidate = [directory stringByAppendingPathComponent: name];
      if ([manager isExecutableFileAtPath: candidate])
        {
          return candidate;
        }
    }
  return nil;
}

+ (NSError *) errorForOutput: (NSString *)output remote: (NSString *)remote
{
  NSString *reason = GSSharingRcloneLastError(output != nil ? output : @"");
  NSString *lower = [output lowercaseString];

  if ([lower rangeOfString: @"rclone_config_pass"].location != NSNotFound
    || [lower rangeOfString: @"configuration password"].location != NSNotFound
    || [lower rangeOfString: @"unable to decrypt configuration"].location != NSNotFound
    || [lower rangeOfString: @"couldn't decrypt configuration"].location != NSNotFound)
    {
      return GSSharingRcloneError(GSSharingRcloneErrorNeedsPassword,
        @"rclone's configuration is encrypted: its password is needed.", reason);
    }
  if ([lower rangeOfString: @"couldn't fetch token"].location != NSNotFound
    || [lower rangeOfString: @"invalid_grant"].location != NSNotFound
    || [lower rangeOfString: @"token expired"].location != NSNotFound
    || [lower rangeOfString: @"cannot fetch token"].location != NSNotFound)
    {
      NSString *hint = [remote length] > 0
        ? [NSString stringWithFormat:
             @"The sign-in to %@ has expired. Run \"rclone config reconnect %@:\" in a terminal.",
             remote, remote]
        : @"An rclone sign-in has expired. Run \"rclone config reconnect\" for the remote in a terminal.";

      return GSSharingRcloneError(GSSharingRcloneErrorExpiredToken, hint, reason);
    }
  if ([lower rangeOfString: @"doesn't support public links"].location != NSNotFound
    || [lower rangeOfString: @"not supported"].location != NSNotFound)
    {
      return GSSharingRcloneError(GSSharingRcloneErrorNoLinks,
        @"This remote can't make links to files.", reason);
    }
  return GSSharingRcloneError(GSSharingRcloneErrorFailed,
    @"rclone couldn't do it.", reason);
}

/* Remotes from `rclone listremotes --long`: "name:   type" per line. */
+ (NSArray *) remotesFromListing: (NSString *)listing
{
  NSMutableArray *remotes = [NSMutableArray array];
  NSDictionary *names = GSSharingRcloneBackendNames();
  NSEnumerator *e = [[listing componentsSeparatedByString: @"\n"] objectEnumerator];
  NSString *line;

  while ((line = [e nextObject]) != nil)
    {
      NSRange colon = [line rangeOfString: @":"];
      NSString *name;
      NSString *type;

      if (colon.location == NSNotFound || colon.location == 0)
        {
          continue;
        }
      name = [line substringToIndex: colon.location];
      type = [[line substringFromIndex: NSMaxRange(colon)]
               stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([names objectForKey: type] == nil)
        {
          continue;
        }
      [remotes addObject: [[[GSSharingRcloneRemote alloc] initWithName: name
                                                                 type: type] autorelease]];
    }
  return remotes;
}

+ (NSArray *) remotesWithPassword: (NSString *)password error: (NSError **)error
{
  NSArray *remotes = nil;

  [cacheLock lock];
  if (cachedRemotes != nil && cachedAt != nil
    && -[cachedAt timeIntervalSinceNow] < GSSharingRcloneCacheSeconds)
    {
      remotes = [[cachedRemotes retain] autorelease];
    }
  [cacheLock unlock];
  if (remotes != nil)
    {
      return remotes;
    }
  return [self fetchRemotesWithPassword: password error: error];
}

/* Runs listremotes whatever is kept, and only then replaces what is kept,
   so a sheet reading cachedRemotes during a refresh still sees the old
   list. A failure clears it, as the remotes may no longer be reachable. */
+ (NSArray *) fetchRemotesWithPassword: (NSString *)password error: (NSError **)error
{
  NSArray *remotes = nil;
  NSString *output = nil;
  NSString *errors = nil;
  int status;

  if ([self executablePath] == nil)
    {
      NSError *notInstalled = GSSharingRcloneError(GSSharingRcloneErrorNotInstalled,
        @"rclone isn't installed.", nil);

      [cacheLock lock];
      [cachedRemotes release];
      cachedRemotes = nil;
      [cachedAt release];
      cachedAt = nil;
      [lastError release];
      lastError = [notInstalled retain];
      [cacheLock unlock];
      if (error != NULL)
        {
          *error = notInstalled;
        }
      return nil;
    }
  status = GSSharingRcloneRun([NSArray arrayWithObjects: @"listremotes", @"--long", nil],
                              password, GSSharingRcloneListTimeout,
                              &output, &errors, NULL, nil);
  if (status != 0)
    {
      NSError *failed = [self errorForOutput:
        [NSString stringWithFormat: @"%@\n%@", errors ? errors : @"", output ? output : @""]
                                      remote: nil];

      [cacheLock lock];
      [cachedRemotes release];
      cachedRemotes = nil;
      [cachedAt release];
      cachedAt = nil;
      [lastError release];
      lastError = [failed retain];
      [cacheLock unlock];
      if (error != NULL)
        {
          *error = failed;
        }
      return nil;
    }
  remotes = [self remotesFromListing: output];
  [cacheLock lock];
  [cachedRemotes release];
  cachedRemotes = [remotes retain];
  [cachedAt release];
  cachedAt = [[NSDate alloc] init];
  [lastError release];
  lastError = nil;
  [cacheLock unlock];
  return remotes;
}

+ (void) forgetRemotes
{
  [cacheLock lock];
  [cachedRemotes release];
  cachedRemotes = nil;
  [cachedAt release];
  cachedAt = nil;
  [cacheLock unlock];
}

+ (NSArray *) cachedRemotes
{
  NSArray *remotes;

  [cacheLock lock];
  remotes = [[cachedRemotes retain] autorelease];
  [cacheLock unlock];
  return remotes;
}

+ (NSError *) lastRemotesError
{
  NSError *error;

  [cacheLock lock];
  error = [[lastError retain] autorelease];
  [cacheLock unlock];
  return error;
}

+ (void) remotesRefreshed: (id)unused
{
  [[NSNotificationCenter defaultCenter]
    postNotificationName: GSSharingRcloneRemotesDidChangeNotification
                  object: self];
}

/* A refresh asked for while one runs (with a password just typed, say)
   runs right after it, and observers hear once, about the last one. */
+ (void) refreshRemotes: (NSString *)password
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  BOOL again;

  [password retain];
  do
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];

      [self fetchRemotesWithPassword: password error: NULL];
      [password release];
      password = nil;
      [cacheLock lock];
      again = refreshAgain;
      if (again)
        {
          password = refreshPassword;
          refreshPassword = nil;
          refreshAgain = NO;
        }
      else
        {
          refreshing = NO;
        }
      [cacheLock unlock];
      [inner release];
    }
  while (again);
  [self performSelectorOnMainThread: @selector(remotesRefreshed:)
                         withObject: nil
                      waitUntilDone: NO];
  [pool release];
}

+ (void) refreshRemotesInBackgroundWithPassword: (NSString *)password
{
  BOOL already;

  [cacheLock lock];
  already = refreshing;
  refreshing = YES;
  if (already)
    {
      /* A password asked for earlier is kept if this call has none. */
      refreshAgain = YES;
      if (password != nil)
        {
          [refreshPassword release];
          refreshPassword = [password copy];
        }
    }
  [cacheLock unlock];
  if (already == NO)
    {
      [NSThread detachNewThreadSelector: @selector(refreshRemotes:)
                               toTarget: self
                             withObject: password];
    }
}

@end


@implementation GSSharingRcloneTransfer

- (id) initWithFile: (NSString *)path
             remote: (GSSharingRcloneRemote *)remote
             folder: (NSString *)folder
{
  if ((self = [super init]) != nil)
    {
      _file = [path copy];
      _remote = [remote retain];
      if ([folder length] == 0)
        {
          folder = [NSString stringWithFormat: @"Shared from %@", GSSharingRcloneAppName()];
        }
      _folder = [folder copy];
      _lock = [[NSLock alloc] init];
    }
  return self;
}

- (void) dealloc
{
  [_file release];
  [_remote release];
  [_folder release];
  [_password release];
  [_remotePath release];
  [_lock release];
  [super dealloc];
}

- (void) setDelegate: (id)delegate
{
  _delegate = delegate;
}

- (id) delegate
{
  return _delegate;
}

- (void) setPassword: (NSString *)password
{
  NSString *copy = [password copy];

  [_password release];
  _password = copy;
}

- (GSSharingRcloneRemote *) remote
{
  return _remote;
}

- (NSString *) file
{
  return _file;
}

- (NSString *) remotePath
{
  NSString *path;

  [_lock lock];
  path = [[_remotePath retain] autorelease];
  [_lock unlock];
  return path;
}

- (NSString *) remoteDisplayPath
{
  NSString *path = [self remotePath];
  NSString *prefix = [NSString stringWithFormat: @"%@:", [_remote name]];

  if ([path hasPrefix: prefix])
    {
      return [NSString stringWithFormat: @"%@: %@", [_remote name],
                       [path substringFromIndex: [prefix length]]];
    }
  return path;
}

- (BOOL) isCancelled
{
  BOOL cancelled;

  [_lock lock];
  cancelled = _cancelled;
  [_lock unlock];
  return cancelled;
}

- (void) cancel
{
  NSTask *task;

  [_lock lock];
  _cancelled = YES;
  task = [_task retain];
  [_lock unlock];
  if ([task isRunning])
    {
      [task terminate];
    }
  [task release];
}

/* The delegate, on the main thread. */
- (void) tellProgress: (NSNumber *)fraction
{
  if ([self isCancelled] == NO)
    {
      [_delegate rcloneTransfer: self didProgress: [fraction doubleValue]];
    }
}

- (void) tellLink: (NSURL *)link
{
  _running = NO;
  [_delegate rcloneTransfer: self didFinishWithLink: link];
  [self release];
}

- (void) tellError: (NSError *)error
{
  _running = NO;
  [_delegate rcloneTransfer: self didFailWithError: error];
  [self release];
}

- (void) fail: (NSError *)error
{
  if ([self isCancelled])
    {
      error = GSSharingRcloneError(GSSharingRcloneErrorCancelled,
        @"The upload was cancelled.", nil);
    }
  [self performSelectorOnMainThread: @selector(tellError:)
                         withObject: error
                      waitUntilDone: NO];
}

/* A name not yet in the folder: "Report.pdf", "Report (2).pdf", ... */
- (NSString *) freeNameIn: (NSString *)listing
{
  NSString *name = [_file lastPathComponent];
  NSString *base = [name stringByDeletingPathExtension];
  NSString *extension = [name pathExtension];
  NSSet *taken = [NSSet setWithArray: [listing componentsSeparatedByString: @"\n"]];
  NSUInteger n = 2;

  while ([taken containsObject: name])
    {
      name = [NSString stringWithFormat: @"%@ (%lu)", base, (unsigned long)n++];
      if ([extension length] > 0)
        {
          name = [name stringByAppendingPathExtension: extension];
        }
    }
  return name;
}

/* The next part of what the task writes to the pipe, or nil at its end.
   On Windows GNUstep's -availableData raises for a pipe (error 232, "The
   pipe is being closed") as soon as it has nothing to read, so the pipe
   is polled there: as much as it holds, until the task has exited and the
   pipe is drained. A read that raises ends the reading anywhere: an
   exception here would end the app, on this thread. */
static NSData *
GSSharingRcloneNextChunk(NSFileHandle *reader, NSTask *task)
{
  NSData *chunk = nil;

  NS_DURING
    {
#if defined(_WIN32)
      HANDLE handle = (HANDLE)[reader nativeHandle];

      for (;;)
        {
          DWORD available = 0;

          if (PeekNamedPipe(handle, NULL, 0, NULL, &available, NULL) == 0)
            {
              break;
            }
          if (available > 0)
            {
              chunk = [reader readDataOfLength: available];
              break;
            }
          if ([task isRunning] == NO)
            {
              break;
            }
          Sleep(100);
        }
#else
      chunk = [reader availableData];
#endif
    }
  NS_HANDLER
    {
      chunk = nil;
    }
  NS_ENDHANDLER
  return ([chunk length] > 0) ? chunk : nil;
}

/* The upload, reading rclone's JSON log for its progress. */
- (int) upload: (NSString *)destination errors: (NSString **)errorText
{
  NSString *path = [GSSharingRclone executablePath];
  NSTask *task = [[NSTask alloc] init];
  NSPipe *errPipe = [NSPipe pipe];
  NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:
    [[NSProcessInfo processInfo] environment]];
  NSFileHandle *reader;
  NSMutableData *pending = [NSMutableData data];
  NSMutableString *log = [NSMutableString string];
  NSData *chunk;
  int status = -1;

  [environment setObject: @"false" forKey: @"RCLONE_ASK_PASSWORD"];
  [environment removeObjectForKey: @"RCLONE_CONFIG_PASS"];
  if ([_password length] > 0)
    {
      [environment setObject: _password forKey: @"RCLONE_CONFIG_PASS"];
    }
  [task setLaunchPath: path];
  [task setArguments: [NSArray arrayWithObjects: @"copyto", _file, destination,
                               @"--use-json-log", @"--stats", @"1s",
                               @"--stats-log-level", @"NOTICE", nil]];
  [task setEnvironment: environment];
  [task setStandardInput: [NSFileHandle fileHandleWithNullDevice]];
  [task setStandardOutput: [NSFileHandle fileHandleWithNullDevice]];
  [task setStandardError: errPipe];
  NS_DURING
    {
      [task launch];
    }
  NS_HANDLER
    {
      [task release];
      task = nil;
    }
  NS_ENDHANDLER
  if (task == nil)
    {
      return -1;
    }
  [_lock lock];
  _task = task;
  _uploadStarted = YES;
  [_lock unlock];
  reader = [errPipe fileHandleForReading];
  while ((chunk = GSSharingRcloneNextChunk(reader, task)) != nil)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      const char *bytes;
      NSUInteger start = 0;
      NSUInteger i;

      [pending appendData: chunk];
      bytes = [pending bytes];
      for (i = 0; i < [pending length]; i++)
        {
          if (bytes[i] == '\n')
            {
              NSData *lineData = [pending subdataWithRange: NSMakeRange(start, i - start)];
              id entry = nil;

              NS_DURING
                {
                  entry = [NSJSONSerialization JSONObjectWithData: lineData
                                                          options: 0
                                                            error: NULL];
                }
              NS_HANDLER
                {
                  entry = nil;
                }
              NS_ENDHANDLER
              if ([entry isKindOfClass: [NSDictionary class]])
                {
                  NSDictionary *stats = [entry objectForKey: @"stats"];
                  NSString *level = [entry objectForKey: @"level"];
                  NSString *message = [entry objectForKey: @"msg"];

                  if ([stats isKindOfClass: [NSDictionary class]])
                    {
                      double done = [[stats objectForKey: @"bytes"] doubleValue];
                      double total = [[stats objectForKey: @"totalBytes"] doubleValue];

                      if (total > 0)
                        {
                          [self performSelectorOnMainThread: @selector(tellProgress:)
                                                 withObject: [NSNumber numberWithDouble: done / total]
                                              waitUntilDone: NO];
                        }
                    }
                  else if ([level isKindOfClass: [NSString class]]
                    && ([level isEqualToString: @"error"] || [level isEqualToString: @"critical"])
                    && [message isKindOfClass: [NSString class]])
                    {
                      [log appendFormat: @"ERROR : %@\n", message];
                    }
                }
              else
                {
                  NSString *text = [[[NSString alloc] initWithData: lineData
                                                          encoding: NSUTF8StringEncoding] autorelease];

                  if (text != nil)
                    {
                      [log appendFormat: @"%@\n", text];
                    }
                }
              start = i + 1;
            }
        }
      [pending replaceBytesInRange: NSMakeRange(0, start) withBytes: NULL length: 0];
      [pool release];
    }
  /* If a read error ended the loop while rclone still writes, a full pipe
     would block it and the wait below with it: closing this end makes its
     writes fail instead. The result is the exit status either way. */
  NS_DURING
    {
      [reader closeFile];
    }
  NS_HANDLER
    {
    }
  NS_ENDHANDLER
  [task waitUntilExit];
  status = [task terminationStatus];
  [_lock lock];
  _task = nil;
  [_lock unlock];
  [task release];
  if (errorText != NULL)
    {
      *errorText = log;
    }
  return status;
}

- (void) run: (id)unused
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *folderPath = [NSString stringWithFormat: @"%@:%@", [_remote name], _folder];
  NSString *listing = nil;
  NSString *errors = nil;
  NSString *output = nil;
  NSString *name;
  NSString *destination;
  NSString *linkText;
  NSURL *link;
  NSMutableArray *linkArgs;
  int status;

  if ([GSSharingRclone executablePath] == nil)
    {
      [self fail: GSSharingRcloneError(GSSharingRcloneErrorNotInstalled,
                    @"rclone isn't installed.", nil)];
      [pool release];
      return;
    }

  /* What is in the folder already (none, if it isn't there yet). */
  status = GSSharingRcloneRun([NSArray arrayWithObjects: @"lsf", folderPath,
                                       @"--files-only", nil],
                              _password, GSSharingRcloneListTimeout,
                              &listing, &errors, &_task, _lock);
  if ([self isCancelled])
    {
      [self fail: nil];
      [pool release];
      return;
    }
  if (status != 0 && status != 3)
    {
      [self fail: [GSSharingRclone errorForOutput: errors remote: [_remote name]]];
      [pool release];
      return;
    }
  name = [self freeNameIn: (status == 0 ? listing : @"")];
  destination = [NSString stringWithFormat: @"%@/%@", folderPath, name];
  [_lock lock];
  [_remotePath release];
  _remotePath = [destination copy];
  [_lock unlock];

  status = [self upload: destination errors: &errors];
  if ([self isCancelled])
    {
      /* An interrupted upload may leave part of the file there. */
      GSSharingRcloneRun([NSArray arrayWithObjects: @"deletefile", destination, nil],
                         _password, GSSharingRcloneDeleteTimeout,
                         NULL, NULL, NULL, nil);
      [self fail: nil];
      [pool release];
      return;
    }
  if (status != 0)
    {
      [self fail: [GSSharingRclone errorForOutput: errors remote: [_remote name]]];
      [pool release];
      return;
    }

  linkArgs = [NSMutableArray arrayWithObjects: @"link", destination, nil];
  [linkArgs addObjectsFromArray: [_remote linkArguments]];
  status = GSSharingRcloneRun(linkArgs, _password, GSSharingRcloneLinkTimeout,
                              &output, &errors, &_task, _lock);
  if ([self isCancelled])
    {
      [self fail: nil];
      [pool release];
      return;
    }
  linkText = [output stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  link = ([linkText length] > 0) ? [NSURL URLWithString: linkText] : nil;
  if (status != 0 || link == nil || [link scheme] == nil)
    {
      NSError *error = (status == -1)
        ? GSSharingRcloneError(GSSharingRcloneErrorFailed,
            @"rclone took too long to make the link.", nil)
        : [GSSharingRclone errorForOutput: errors remote: [_remote name]];

      [self fail: error];
      [pool release];
      return;
    }
  [self performSelectorOnMainThread: @selector(tellLink:)
                         withObject: link
                      waitUntilDone: NO];
  [pool release];
}

- (void) start
{
  if (_running)
    {
      return;
    }
  _running = YES;
  /* Kept until the delegate has been told. */
  [self retain];
  [NSThread detachNewThreadSelector: @selector(run:)
                           toTarget: self
                         withObject: nil];
}

@end
