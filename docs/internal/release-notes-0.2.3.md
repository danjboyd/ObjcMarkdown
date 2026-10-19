# Release notes: 0.2.3

Dan chose (2026-10-17) to ship Share (#170) in 0.2.3, from `main`, rather than 0.2.3 from rc3 and Share as 0.3.0. Changes are since v0.2.2; rc1 to rc3 were candidates without Share.

---

**New: Share.** File > Share (and the Share button in the toolbar) turns the open document, unsaved edits included, into what a colleague needs and hands it on, without a Save panel.

- **Share as** PDF, Word Document, Markdown File or HTML. The share sheet shows a preview and lets you switch format; it opens with your last choice for each destination.
- **Email as** PDF, Word, Markdown or HTML attaches the file to a new draft in your mail app. **Email as > In the Message** puts the rendered document in the message body instead (Thunderbird and macOS Mail directly; other mail apps get a draft with the document on the clipboard to paste).
- **Copy Rendered** puts the formatted document on the clipboard for Teams, Outlook, Mail or Word. **Copy for Slack** formats it the way Slack expects.
- **Before sending**, the sheet points out what the reader would miss: images and links that are only on your computer, math and Mermaid diagrams in formats that can't show them. It offers a PDF or a `.zip` with the images instead.
- **Share just the selection** when text is selected.
- **Links through rclone** (optional): with [rclone](https://rclone.org) installed and a OneDrive, Google Drive, Dropbox or similar remote set up, the sheet offers "Link on <remote>": it uploads a copy into "Shared from Markdown Viewer", puts the link on the clipboard and says who can open it (OneDrive: your organization, view only). Cancel removes a partial upload. The app never reads or stores your cloud credentials.

On **Linux** the sheet comes from libs-sharing, a GNUstep implementation of Apple's `NSSharingService` API: email through the desktop's email portal or `xdg-email` (Evolution, Thunderbird and KMail take attachments; with webmail as the mail handler, a notice offers the file to drag into the browser), Open With, Show in Folder, Copy File (pastes into GNOME Files), and the file can be dragged out of the sheet into a browser, a mail app or the file manager. The Flatpak shares through the desktop portals and doesn't offer rclone.

On **macOS** Share goes through the Mac's own share menu: Mail, Messages, AirDrop and your apps' share extensions. Email as opens a Mail draft with the document as the message body, or attached in the format you pick; with another mail app as your default, a draft opens and Markdown Viewer offers the file to attach. rclone remotes appear in the same menu as "Link on <remote>".

On **Windows** Share opens the Windows share sheet (Windows 10 and 11). Where Windows has none (Windows Server), Markdown Viewer's own sheet opens instead, with Email, Copy, Save a Copy, Show in Folder, Open With and any rclone links; if the Windows sheet doesn't open, a notice offers the file. Email opens a new message in your desktop mail client (classic Outlook, Thunderbird) with the document attached; with no such client (the new Outlook, webmail) it opens a `mailto:` draft and tells you where the file is. Show in Folder opens Explorer with the file selected. Copy Rendered puts HTML and RTF on the clipboard for Outlook, Teams or Word, and Copy File pastes as the file in Explorer, Outlook and Teams. rclone is found on PATH and where Scoop, WinGet and Chocolatey put it.

**Also new**
- Preferences > Menus: a menu bar or a menu button, for this app only (#185).
- Linux packages bundle Adwaita 0.1.0-alpha15 (b2d4326).
- Linux: files drag out of the app and copied files paste into file managers (GNUstep fixes the packages carry until they're upstream).
- Vim key bindings (Preferences > Editor, off by default) behave much more like Vim (#165): `.` repeats changes and inserts; `A`, `I`, `X`, `J`, `Y`, `cc`, `x`, `dw`, `3G` and the linewise `dj`, `dk`, `dG`, `dgg` do what Vim does; new are `f F t T ; ,`, `W B E`, `{ }`, `%`, `+ -`, `r`, `~`, `s S`, text objects such as `ci"` and `da(`, registers `"a` to `"z` and `"_`, and more Visual mode commands.

**Fixed since 0.2.2**
- Linux: Alt+F4 (or the window's close in the window manager) asks to save unsaved edits instead of quitting (#158).
- File > Close closes the selected window tab while others remain open (#135).
- Split and Read: a large document opens without repeated layouts (#121, #154); the outline lays out again only when it fits (#166).
- Source editor: no ligatures, so "fi" keeps two columns (#125).
- Updater: says at the next launch why an update didn't install (#134); no Check for Updates where the package has no updater (#122).
- Pandoc hints for each platform; Homebrew's pandoc is found on macOS (#131).
- Windows: web links open in the browser (#144); task boxes fall back to Segoe UI Symbol (#162); Export as PDF, Print and Share as PDF no longer hang on headless Edge's output (#232), and without Pandoc they keep headings, tables, code, quotes, local images and column alignment, with math as readable TeX (#169); the MSI bundles WinUITheme 0.1.0-alpha8 (906e462) with the carried libs-back and libs-gui scroller fix (#157, #156) and only the TinyTeX math needs (#127).
- macOS: says the app stays open after its last window closes (#136).

**Known issues**
- Windows: files can't be dragged out of the app yet (#213); use Copy File.
- Windows: typing in the source editor uses more CPU than it should on large documents (#164); printing goes through a PDF in the browser (#82).
- macOS: pasting Copy Rendered and Copy for Slack into Mail, Teams and Slack hasn't been checked by eye yet (#177). If Slack shows Copy for Slack's `*bold*` as typed, a follow-up adds an HTML version.
- rclone links haven't been made with a real remote yet, only a stand-in (#198).
- Links through GNOME Online Accounts aren't there yet (#197); use rclone.
- Linux Flatpak: Share > Email to a mail app the email portal doesn't know falls back to a draft and an "attach this file" notice.
- Linux Flatpak: no rclone links (the sandbox doesn't run rclone); the AppImage has them.

---

## Before this ships (checklist)

- [x] Dan: version 0.2.3, with Share (2026-10-17).
- [x] Dan: OK to tag v0.2.3-rc4 from main (c18b765, 2026-10-17).
- [x] rc4 macOS: NO-GO. The Share toolbar item exported a PDF whenever AppKit asked for its items: alerts at launch, nested exports (#236). Fixed by #237: it exports only when a share loads the file. Share is new in 0.2.3 and #236 never shipped, so it isn't listed under Fixed.
- [x] v0.2.3-rc5 tagged on main 79e1c27 with Dan's go: rc4 + #237 + the Vim fidelity pass (#165, TextViewVimKit 571902f).
- [x] rc5 Linux AppImage + Flatpak smoke, including Vim on and off: PASS (#170 comment 6274652640). rc4 Linux AppImage + Flatpak PASS (#170 comment 6245342156).
- [ ] rc5 macOS dmg round: GO from Markdown Viewer macOS. Also #177.
- [ ] rc5 Windows MSI round on Server 2022: GO from Markdown Viewer Windows.
- [ ] Dan: go for v0.2.3 final, tagged on the tested commit (79e1c27) as the rc tags were (annotated "ObjcMarkdown 0.2.3").
- [x] Windows check of Share on CI MSIs on Server 2022 (#198 comment 6230285785): rclone and built-ins pass; WinUITheme 906e462.
- [x] **Must-merge: #233** (merged d597637) (#232: Share/Export as PDF and Print can hang the app on Windows; headless Edge blocked on an unread stderr pipe). Green, reviewed.
- [x] Linux check of Share on the CI AppImage of main (#170 comment 6229907288). Flatpak built green, not checked by eye again.
- [x] Merge #225 + libs-sharing#4 (rclone remotes kept during a refresh; green on all three). Also #231 (math symbols) and #234 (TeX tools write to files), both green; they merge cleanly together. libs-sharing#5 optional (GNUstep only; review asked for a pending-job count).
- [x] #226 (Windows: PDF/Print without Pandoc, #169): in (Dan marked it ready 2026-10-17); merge.
- [ ] #198: one real rclone link with Dan's own remote (optional for the release; the stand-in checks pass).
- [ ] Release body: add the macOS/Windows paragraphs and the bundled theme commits.

## Tagging the final (one step once Windows says GO)

**Commit:** `79e1c27` (main; the rc5 commit every platform tested). Tag the final on that same commit, as 0.2.2 was (`v0.2.2` and `v0.2.2-rc3` are both `d260007`). If the README screenshots PR merges first and Dan wants the tag's tree to have it, tag that merge commit instead, but only if `git diff --stat 79e1c27 <merge>` touches nothing but `README.md` and `docs/`. The packages would then be rebuilt from it, so smoke-test the AppImage once.

**Tag** (Dan's go; annotated like the rc tags):

```sh
git fetch origin && git tag -a v0.2.3 -m "ObjcMarkdown 0.2.3" 79e1c27 && git push origin v0.2.3
```

**After the tag** (all five tag workflows: linux-appimage, linux-flatpak, macos, windows-packaging, ci-image):
- [ ] All five runs on `v0.2.3` are green (`gh run list -R danjboyd/ObjcMarkdown --branch v0.2.3`).
- [ ] Release `v0.2.3`: **not a draft, not a pre-release, Latest**, 13 assets like rc5 (AppImage + zsync + debug + diagnostics + metadata + feed, Flatpak, dmg, MSI, portable zip, Windows diagnostics + metadata + feed).
- [ ] gh-pages has three new "Publish … stable update feed" commits (linux, windows, macos) after the tag. `updates/linux/stable.json` and `updates/windows/stable.json` name 0.2.3, and `updates/macos/appcast.xml` has `shortVersionString` 0.2.3. These steps are skipped for tags with "-", so this is the first time 0.2.3 reaches the feeds.
- [ ] The same-SHA trap. It bit ScreenshotTool v0.3.0 (2026-10-19): its final was tagged on the rc's commit, GitHub Pages didn't redeploy for a commit it had already deployed, the feeds stayed stale, and its release stayed a draft (run 39302299075). ScreenshotTool recovered by landing a commit on main, dispatching its feed redeploy, and running `gh release edit v0.3.0 --draft=false`.
  - Here it should not bite: ObjcMarkdown's feeds skip "-" tags, so no rc ever published from `79e1c27`, and each publish pushes a new gh-pages commit (`packaging/ci/publish-update-feed.sh`). 0.2.2 on rc3's `d260007` published fine (2026-10-14).
  - Still verify. If a feed is stale or the release isn't published, don't re-tag. Rerun the failed "Publish … Stable Update Feed" job (`gh run rerun <id> --failed`); it pushes a fresh gh-pages commit and Pages redeploys. Then `gh release edit v0.2.3 --draft=false --prerelease=false --latest` if needed, and check the boxes above again.
- [ ] Release body: the user-facing notes above (from **New: Share** through **Known issues**) above the workflow's platform notes, with the bundled theme commits (Linux Adwaita b2d4326, Windows WinUITheme 906e462).
- [ ] An installed 0.2.2 sees the update: a Linux AppImage on a private display, Check for Updates offers 0.2.3. Windows and macOS sessions do the same on their builds.
- [ ] Then: README "Windows screenshots will follow" follow-up PR; merge #248 (share sheet, 0.2.4); close the 0.2.3 milestone (Dan).
