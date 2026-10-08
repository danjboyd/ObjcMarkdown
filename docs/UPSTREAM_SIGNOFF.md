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
