/* Reproducer: on Windows, -[NSFileHandle availableData] on the read end of
   an NSPipe raises NSFileHandleOperationException ("unable to read from
   descriptor", error 232 "The pipe is being closed") when the pipe holds
   nothing yet, instead of blocking until data arrives (or returning empty
   data at end of file, as on other platforms).

   The child is cmd.exe: it waits about two seconds (ping), then writes one
   line to its stderr, which is the pipe.

   Build (MSYS2 CLANG64 or GCC, with GNUstep's make):
     a GNUmakefile with TOOL_NAME = pipe_available_data
     and pipe_available_data_OBJC_FILES = this file, then `make`.
   Run: obj/pipe_available_data.exe

   Expected: "read N bytes" once the line arrives, then "end of file".
   Seen (gnustep-base 1.31.1, Windows 11 and Server 2022): the exception,
   at once, before the child has written anything. */

#import <Foundation/Foundation.h>

int
main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSTask *task = [NSTask new];
  NSPipe *pipe = [NSPipe pipe];
  NSFileHandle *reader = [pipe fileHandleForReading];
  NSData *chunk;
  int failed = 0;

  [task setLaunchPath: @"C:\\Windows\\System32\\cmd.exe"];
  [task setArguments: [NSArray arrayWithObjects: @"/c",
    @"ping -n 3 127.0.0.1 >nul & echo written-to-stderr 1>&2", nil]];
  [task setStandardInput: [NSFileHandle fileHandleWithNullDevice]];
  [task setStandardOutput: [NSFileHandle fileHandleWithNullDevice]];
  [task setStandardError: pipe];
  [task launch];

  NS_DURING
    {
      while ((chunk = [reader availableData]) != nil && [chunk length] > 0)
        {
          printf("read %lu bytes\n", (unsigned long)[chunk length]);
        }
      printf("end of file\n");
    }
  NS_HANDLER
    {
      printf("raised: %s: %s\n", [[localException name] UTF8String],
             [[localException reason] UTF8String]);
      failed = 1;
    }
  NS_ENDHANDLER

  [task waitUntilExit];
  [task release];
  [pool release];
  return failed;
}
