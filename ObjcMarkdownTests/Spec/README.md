# Spec conformance data

`OMSpecConformanceTests` renders every example in these files and checks the
result against the example's expected HTML.

- `spec.txt`: the GitHub Flavored Markdown spec, version 0.29, from
  [cmark-gfm](https://github.com/github/cmark-gfm) tag `0.29.0.gfm.13`
  (`test/spec.txt`), the version vendored in `third_party/cmark-gfm`. It
  contains the CommonMark examples plus the GFM extensions. Licensed
  [CC-BY-SA 4.0](http://creativecommons.org/licenses/by-sa/4.0/).
- `extensions.txt`: cmark-gfm's extension examples (tables, strikethrough,
  autolinks, tag filter, footnotes, task lists), from the same tag
  (`test/extensions.txt`). Part of cmark-gfm, under its BSD-2-Clause license
  (`third_party/cmark-gfm/LICENSE`).
- `known-failures.txt`: the checks each example is known to fail, grouped by
  reason (raw HTML shown as text, empty link destinations, the link scheme
  allowlist, footnote references not yet linked).

## Checks

For each example:

- `crash`: rendering raised an exception or returned nothing.
- `text`: the visible text of the expected HTML (tags and images removed) is
  missing from the rendered text. Characters the renderer adds, such as list
  bullets, are allowed; characters it drops are not.
- `em`, `strong`, `del`, `code`, `pre`, `heading`: text the expected HTML puts
  in that element is rendered without the matching style (italic, bold,
  struck, monospaced, heading anchor).
- `link`, `href`: text inside `<a href>` is not a link, or links somewhere
  else.

A check that fails and is not listed in `known-failures.txt` fails the test.
An entry that now passes is reported in the test log, so the list can be
trimmed. To regenerate the list after a renderer change:

    OM_SPEC_WRITE_KNOWN_FAILURES=$PWD/ObjcMarkdownTests/Spec/known-failures.txt \
      LD_LIBRARY_PATH=$PWD/ObjcMarkdown/obj:/usr/GNUstep/System/Library/Libraries \
      xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle

The regenerated file has no reasons, only section names. Review the diff:
new entries are regressions unless explained, and explained ones should get
their reason back.

Each run logs the pass rate per section and in total.
