# Sprint 1 Formatting QA Matrix

Date: 2026-02-19
Scope: Issue #5 (`Sprint-1 editing correctness closeout`)

Status key:
- `PASS`: behavior matches expectation
- `FAIL`: behavior diverges from expectation
- `PENDING`: not yet manually executed

## Preconditions

1. Build latest app: `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && gmake`
2. Launch fixture: `gmake run TableRenderDemo.md`
3. Validate in both `Edit` and `Split` modes.

## Automated Baseline (2026-02-19)

- `gmake`: PASS
- `xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle`: PASS
- Relevant suites:
  - `OMDInlineToggleTests` (7 tests)
  - `OMDSourceTextViewTests` (17 tests)
  - `OMDSourceTextViewStructuredNewlineTests` (4 tests)

## Inline Toggle Commands

| Case | Mode(s) | Steps | Expected | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| Bold toggle on selected word | Edit + Split | Select word, trigger bold, trigger bold again | First press wraps with `**`; second press restores plain text | PASS | Covered by `OMDInlineToggleTests`; UAT confirmed (Ctrl/Cmd+B fixed) |
| Italic toggle on selected word | Edit + Split | Select word, trigger italic, trigger italic again | First press wraps with `*`; second press restores plain text | PASS | Covered by `OMDInlineToggleTests`; UAT confirmed (Ctrl/Cmd+I fixed) |
| Inline code toggle on selected word | Edit + Split | Select word, trigger inline code, trigger inline code again | First press wraps with `` ` ``; second press restores plain text | PASS | Covered by `OMDInlineToggleTests` |
| Mixed multiline selection toggle (bold) | Edit + Split | Select lines with mixed wrapped/unwrapped words; toggle bold twice | Pass 1 normalizes all lines to wrapped; pass 2 unwraps all lines | PASS | Covered by `OMDInlineToggleTests` |
| Selection inside wrapper toggle (bold) | Edit + Split | Place selection inside `**wrapped**` text; toggle bold twice | First press unwraps surrounding wrapper; second press re-wraps | PASS | Covered by `OMDInlineToggleTests` |

## List and Structure Commands

| Case | Mode(s) | Steps | Expected | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| Tab indents bullet line | Edit + Split | Put caret in bullet list line, press `Tab` | List line indents one level | PASS | Covered by `OMDSourceTextViewTests` |
| Shift+Tab outdents bullet line | Edit + Split | Put caret in indented bullet list line, press `Shift+Tab` | List line outdents one level | PASS | Covered by `OMDSourceTextViewTests` |
| Enter continues task list | Edit + Split | Press `Enter` at end of `- [ ] item` line | Next line continues task marker | PASS | Covered by `OMDSourceTextViewStructuredNewlineTests` |
| Enter exits empty task item | Edit + Split | On empty `- [ ] ` line, press `Enter` | Leaves list structure cleanly | PASS | Covered by `OMDSourceTextViewStructuredNewlineTests` |
| Enter exits empty blockquote | Edit + Split | On empty `> ` line, press `Enter` | Leaves quote structure cleanly | PASS | Covered by `OMDSourceTextViewStructuredNewlineTests` |

## Exit Criteria

1. All rows marked `PASS` in both `Edit` and `Split`.
2. Any `FAIL` rows have linked fixes and rerun evidence.
3. Close Issue #5 (tracked as `ClosedIssues.md` issue 38).
