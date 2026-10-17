# Release notes draft: Share

Draft for the release that brings Share (#170). The version is Dan's call: ReleaseCoordinator suggests 0.2.3 final from rc3 without Share, then this as 0.3.0 from main. The text below doesn't name a version, so it works either way. Changes are since v0.2.3-rc3 (23d05c2).

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

On **Windows** Share opens the Windows share sheet (Windows 10 and 11). Where there's no share sheet (Windows Server), or it doesn't open, a notice offers the file: Show in Folder, Copy File and Open With. Email opens a new message in your desktop mail client (classic Outlook, Thunderbird) with the document attached; with no such client (the new Outlook, webmail) it opens a `mailto:` draft and tells you where the file is. Show in Folder opens Explorer with the file selected. Copy Rendered puts HTML and RTF on the clipboard for Outlook, Teams or Word, and Copy File pastes as the file in Explorer, Outlook and Teams. rclone is found on PATH and where Scoop, WinGet and Chocolatey put it.

**Also new**
- Preferences > Menus: a menu bar or a menu button, for this app only (#185).
- Linux packages bundle Adwaita 0.1.0-alpha15 (b2d4326).
- Linux: files drag out of the app and copied files paste into file managers (GNUstep fixes the packages carry until they're upstream).

**Known issues**
- Windows: files can't be dragged out of the app yet (#213); use Copy File.
- Windows: without Pandoc, Export as PDF, Print and Share as PDF give unformatted monospace text (#169; fix in review as #226, which may land before the release); typing in the source editor uses more CPU than it should on large documents (#164); printing goes through a PDF in the browser (#82).
- macOS: pasting Copy Rendered and Copy for Slack into Mail, Teams and Slack hasn't been checked by eye yet (#177). If Slack shows Copy for Slack's `*bold*` as typed, a follow-up adds an HTML version.
- rclone links haven't been made with a real remote yet, only a stand-in (#198).
- Links through GNOME Online Accounts aren't there yet (#197); use rclone.
- Linux Flatpak: Share > Email to a mail app the email portal doesn't know falls back to a draft and an "attach this file" notice.

---

## Before this ships (checklist)

- [ ] Dan: version and tag.
- [ ] macOS by-eye checklist on #170 (comment of 2026-10-17), and #177.
- [ ] Windows check of Share on a CI MSI of main (Windows session, 2026-10-17 night).
- [x] Linux check of Share on the CI AppImage of main (#170 comment 6229907288). Flatpak built green, not checked by eye again.
- [ ] Merge #225 + libs-sharing#4 (rclone remotes kept during a refresh; green on all three). Optionally libs-sharing#5 (share callbacks when uploads finish; GNUstep only) and #231 (math symbols, green).
- [ ] #226 (Windows: PDF/Print without Pandoc, #169): Dan decides if it's in.
- [ ] #198: one real rclone link with Dan's own remote (optional for the release; the stand-in checks pass).
- [ ] Release body: add the macOS/Windows paragraphs and the bundled theme commits.
