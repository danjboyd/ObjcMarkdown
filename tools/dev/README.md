# Developer tools

Scripts for checking MarkdownViewer by eye without touching your desktop,
and for keeping mixed line endings intact. All UI scripts share a work
directory, `$OMD_UI_WORK` (default `/tmp/omd-ui`), holding the display
number, a private HOME, screenshots and the app's log.

## A private GNOME display

```sh
tools/dev/ui-session.sh            # Xvfb + GNOME Shell (X11) on :120 or the next free display
tools/dev/ui-launch.sh doc.md      # the in-tree build, replacing any running copy
tools/dev/ui-shot.sh name          # -> $OMD_UI_WORK/shots/name.png (whole 1600x1000 screen)
tools/dev/ui-dark.sh on|off        # colour scheme for the next launch
tools/dev/ui-stop.sh               # stops the app and the session
```

Drive it with `xdotool` (`export DISPLAY=$(cat $OMD_UI_WORK/display)`).

- The private HOME copies your global GNUstep defaults (Adwaita, header bar
  via `GSX11HandlesWindowDecorations NO`, `NSWindows95InterfaceStyle`) and
  links your themes, but starts MarkdownViewer's own defaults fresh. Read
  them with `HOME=$OMD_UI_WORK/home defaults read MarkdownViewer`.
- Extra app arguments override defaults for one launch, for example
  `ui-launch.sh doc.md -GnomeThemeHeaderBarToolbar NO`.
- The Adwaita theme reads the colour scheme only at launch: run `ui-dark.sh`
  and launch again.
- **The first synthetic click after a launch is often lost**, and a lost
  press can leave a control waiting for a release that never comes. Make the
  first click a harmless one (the Read button in the header bar, about
  x=1209 y=110 when maximised) before clicking anything that matters. If a
  menu or button seems dead, relaunch and warm up first.
- Menus open on click and stay open (`xdotool click 1`, then click an item).
  The context menu on rendered objects and tables needs the right button
  held: `mousedown 3`, screenshot, move, `mouseup 3`.
- The clipboard works through `xclip -selection clipboard -o -t UTF8_STRING`
  once the app has copied something.
- Never stop things with `pkill -f <pattern>`: the pattern can match your own
  shell's command line.

## Mixed line endings

`ObjcMarkdown/OMMarkdownRenderer.m`, `ObjcMarkdownTests/OMMarkdownRendererTests.m`,
some GNUmakefiles and `AGENTS.md` mix CRLF and LF line by line. The Edit
tool and most scripts rewrite the whole file with one ending.

```sh
tools/dev/restore-eol.py ObjcMarkdown/OMMarkdownRenderer.m
git diff --stat                        # should now equal:
git diff HEAD --ignore-cr-at-eol --stat
```
