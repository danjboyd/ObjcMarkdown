# WinUI audit: title bar, menu bar and toolbar (2026-10-08)

MarkdownViewer on Windows under WinUITheme, compared with WinUI's guidance and with Windows 11's own document apps (Notepad, Paint, File Explorer). Done on the Windows dev box: my own instance of the dev build (main of 2026-10-08), README.md in Read mode, light and dark, captured with PrintWindow. I also checked the app's toolbar and menu code and the theme's open issues.

## Which theme this is about

- **The audit used the WinUITheme installed on the dev box: main at 6513c49 (2026-10-08).**
- **The released 0.2.0 MSI ships an older theme.** It ships WinUITheme 48d21f0, from 2026-04-28, which is 88 commits behind main. It's pinned in `packaging/manifests/windows-msi.manifest.json`; the v0.2.0 packaging run logged "HEAD is now at 48d21f0".
  - So MSI users have none of this month's theme work: menus and Windows conventions (winuitheme#24, #39), the CommandBar toolbar (#21), the segmented look (#48), the overlay scroll bars, high contrast.
- The theme's first release, 0.1.0-alpha1 (eb9f8b8), includes all of that, plus the overlay scroll bar fix (winuitheme#87/#88).
- Moving the MSI's pin to it is waiting for Dan's OK. After the move, this audit should be repeated on an installed MSI.

## Where we are

| Area | Today (theme main) | WinUI practice | Gap | Fix belongs in |
|---|---|---|---|---|
| Title text | `README.md  --  ~/git/ObjcMarkdown` | `README.md - Markdown Viewer`, with `*` or `•` when there are unsaved changes | GNUstep's represented-filename format: folder path, no app name, no unsaved marker | Theme (winuitheme#33, open). The app's name is `MarkdownViewer`, with no space |
| Title bar | A 32 px bar: icon, title, caption buttons | The same for a simple app. Document apps put tabs or commands in a taller (48 px) title bar, on Mica | No content in the title bar; no Mica | Theme (#72 tabs, #47 Mica, both open) |
| Chrome rows | Three: title bar (~30 px), menu bar (~32 px), toolbar (~49 px), about 110 px before the content | Two: Notepad has tabs in the title bar plus one menu row; Paint puts its menus in the title bar | One row more than WinUI apps; it reads as classic Win32 | Theme, perhaps with a new app declaration (no issue yet) |
| Menu bar | File, Edit, View, Help, drawn by the theme. Windows conventions done (#24: no app-name menu, About in Help, Exit in File) | WinUI MenuBar: Alt and F10 reach it, access keys, arrow keys | Keyboard access not verified: posted window messages can't drive the theme's in-window menu | Theme. Check with a real keyboard on a VM |
| Toolbar | Plain icon-only items (explorer, Open with a recent-files arrow, Save), a flexible space, then Read/Edit/Split drawn like WinUI's SelectorBar | CommandBar: primary commands, labels allowed, overflow `…` | The app forces icon-only (`OMDToolbarController.m:55`), so the theme can't choose labels | App (one line), after checking that Adwaita's header bar stays icon-only |
| Open with recents | Two buttons in a custom toolbar view | WinUI SplitButton | The theme can't recognise it as one control | Low priority |
| Shortcuts | Redo is Ctrl+Shift+Z | Ctrl+Y (Ctrl+Shift+Z also accepted) | Small convention gap | Theme, the way #24 remaps Quit to Exit |

Already right: the Read/Edit/Split segmented control, the menus' look (#39), the toolbar style (#21), dark mode, the status bar with zoom.

## Recommendations, in order

1. **The title** (winuitheme#33): theme work, plus the app's display name "Markdown Viewer". Users see it on every window and in the taskbar, so it does the most for the least work.
2. **Two rows instead of three.** The theme draws the menu bar and the toolbar's commands in one row: menus left, the toolbar's flexible space, then the commands and Read/Edit/Split right. This is the biggest visual step toward WinUI.
   - Dan's decision: WinUITheme always does this, or the app declares it with a theme-neutral `Info.plist` key, as `GnomeThemeHeaderBarToolbar` does for Adwaita.
   - Both fit AGENTS.md's UI principle: the app keeps one menu and one toolbar either way.
3. **Tabs in the title bar** (winuitheme#72), like Notepad and Terminal.
   - Until then the theme keeps window tabs off by default (winuitheme PR #85, and still in 0.1.0-alpha1), so users get the app's own in-window tab strip (#108). That strip hasn't been checked by eye under WinUITheme yet.
   - The fix for Quit missing unsaved documents in background window tabs is on main (8f03190); it applies once the theme has window tabs.
4. **Check menu keyboard access** with a real keyboard on a VM: Alt, F10, access keys, arrow keys. It's a basic accessibility need, so it should be a release requirement.
5. **Later:** Mica (#47), which may not render on a VM's basic display adapter anyway; letting the theme choose toolbar labels; a split-button look for Open.

## Decisions for Dan

- Single-row chrome: always in WinUITheme, or declared by the app?
- Move the MSI's theme pin from 48d21f0 to 0.1.0-alpha1 (eb9f8b8) for 0.2.1. After that, repeat this audit on an installed MSI.
