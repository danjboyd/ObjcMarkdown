# libs-base (win32): -[NSFileHandle availableData] raises on an empty pipe instead of waiting

**Repository:** gnustep/libs-base
**Reproducer:** [2-libs-base-win32-pipe-availabledata.m](2-libs-base-win32-pipe-availabledata.m)
**Status:** draft, not approved (needs Dan's sign-off in `docs/UPSTREAM_SIGNOFF.md`; GCC check still to run).
**Found:** ObjcMarkdown #198 (libs-sharing's rclone upload read rclone's stderr through `-availableData`; on Windows the app ended with an uncaught exception). libs-sharing works around it with `PeekNamedPipe` and `-readDataOfLength:`.

Everything between the two rules below is the issue as it would be filed:
the first line is its title, the rest its body.

---

win32: -[NSFileHandle availableData] on a pipe raises "unable to read from descriptor" (ERROR_NO_DATA) instead of waiting for data

On Windows, `-availableData` on the read end of an `NSPipe` raises
`NSFileHandleOperationException` ("unable to read from descriptor - ... Code=232
"The pipe is being closed.") as soon as the pipe holds nothing yet. The
documented behaviour, and what the other platforms do, is to wait until some
data arrives, and to return empty data at end of file.

So the usual loop for reading a child process's output as it comes,

```objc
while ((chunk = [reader availableData]) != nil && [chunk length] > 0)
  {
    ...
  }
```

raises on its first pass on Windows. On a thread of its own the exception
ends the program. `-readDataToEndOfFile` on the same pipe works.

**Reproducer** (attached, plain Objective-C with manual retain and release):
an `NSTask` runs `cmd.exe /c "ping -n 3 127.0.0.1 >nul & echo written-to-stderr 1>&2"`
with an `NSPipe` as its stderr, then reads the pipe with `-availableData`.

- Expected: `read N bytes` after about two seconds, then `end of file`.
- Seen (gnustep-base 1.31.1, MSYS2 CLANG64, Windows 11 and Windows Server 2022):
  `raised: NSFileHandleOperationException: unable to read from descriptor - ... Code=232`,
  immediately.

**Where:** `Source/win32/GSFileHandle.m`, `-availableData`. For a handle that
isn't a standard file it sets the handle non-blocking (`setNonBlocking: YES`;
for a pipe that is `PIPE_NOWAIT`) and calls `-read:length:`. `ReadFile` on an
empty non-blocking pipe fails with `ERROR_NO_DATA` (232). The code then
treats only `WSAEINTR` and `WSAEWOULDBLOCK`, which are socket errors, as
"would block", so for a pipe the read falls through to `len < 0` and the
exception.

A pipe's `ERROR_NO_DATA` probably wants the same treatment as
`WSAEWOULDBLOCK`: wait (blocking read of one byte, as the code does for a
socket), then read the rest. `ERROR_BROKEN_PIPE` after the writer has gone is
already mapped to end of file in `-read:length:`.

---

Not filed. To do before asking for sign-off:
- [ ] `tools/upstream/gcc-syntax-check.sh` on the reproducer (on the Linux box).
- [ ] Check libs-base master: is this still the code?
- [ ] Consider sending a patch with a test (Tests/base/NSFileHandle) instead of an issue.
