# Upstream sign-off

Dan's record that he has reviewed an item and that exact version may be
sent upstream (`docs/UPSTREAM_POLICY.md`, stage 2).

A line is added by Dan, or by Claude recording an approval Dan gave in the
chat: explicit, naming the item, given after Claude presented that item's
review document and hash, quoted in Notes. Claude adds nothing else here,
and reads this table before sending anything: nothing is sent whose hash
isn't in it.

- A patch: the commit's hash (`git rev-parse` in the series worktree).
- An issue: `git hash-object` of the draft and of its reproducer.

Any change to an item after its line was added voids the line.

| Date | Item | Hash(es) reviewed | Notes | Sent |
|---|---|---|---|---|
| 2026-10-08 | libs-gui issue 1: `_sanityChecks` makes edits quadratic (`docs/upstream-issues/1-libs-gui-layout-sanity-checks.md`, `.m`) | draft `1511c05778ca77b72bef7a96a5a16c4f2130a849`, reproducer `042d1c0dddbc8c2de38b904b7ea0112c49b07ddf` | approved in chat: "that bug report is approved. file it and then open the next one for my review" | |
| 2026-11-06 | libs-gui: `-[NSView addTrackingRect:...]` running tag (`docs/upstream-patches/libs-gui/0001-NSView-don-t-scan-a-view-s-tracking-rects-to-choose-.patch`, AIManager upstream report #14) | commit `d7e5f5f757ed8355af9a5a89199f91147f8342a9` | approved in chat: "Dan's go for upstream #14 (libs-gui addTrackingRect running max tag, commit d7e5f5f), replacing ask #3994: (1) add a docs/UPSTREAM_SIGNOFF.md line for d7e5f5f quoting this approval, and put the patch with its README row in docs/upstream-patches/libs-gui/, on a branch, pushed (no force), as a PR to danjboyd/ObjcMarkdown, merged once green; (2) re-run the GCC check at send as Stage 3 says; (3) post exactly d7e5f5f with the approved body to gnustep/libs-gui from the fork, and record it with upstream.posted. Nothing else." | |
