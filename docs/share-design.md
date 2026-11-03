# Share: design note

Status: written 2026-10-16; status section refreshed 2026-11-03, after
0.2.6. Tracking issue: #170.

The viewer gets a Share command: one gesture that turns the open document
into the form a colleague needs (a file or pasted content) and hands it to
where they will read it (email, Teams, Slack, Messages, a cloud link). Later
the Linux part becomes a reusable GNUstep library, so other GNUstep apps get
a share sheet too.

## Where it stands (after 0.2.6)

Milestones 1 and 2 shipped together in 0.2.3, and later releases fixed
them up. In milestone 3, rclone links shipped but haven't been tried on a
real remote yet; the GNOME Online Accounts links haven't been started. The
sections after this one are the design as it was written on 2026-10-16.
Where what shipped differs from it, this section says so.

### What shipped

| Release | Share |
|---|---|
| 0.2.3 | Share on all three platforms: File > Share, a Share toolbar item and a share sheet with no Save panel. Formats: PDF, Word, Markdown, HTML. **Email as** each format, or **In the Message** (the rendered document as the body). **Copy Rendered** and **Copy for Slack**. **Checks before sending** (local images and links, math and Mermaid in formats that can't show them), with a PDF or a `.zip` with the images offered instead. **Share just the selection**. **rclone links** ("Link on <remote>"). Linux: libs-sharing's sheet. macOS: Apple's picker, with rclone remotes in it. Windows: the Windows share sheet, and libs-sharing's sheet where Windows has none (Windows Server). |
| 0.2.4 | libs-sharing: Save a Copy opens in the document's folder and keeps the type when a name is typed without an extension (libs-sharing#24); Open With shows the chooser on Windows (libs-sharing#23). |
| 0.2.5 | Toolbar overflow order: Explorer first, then Share, then Open and Save. Each theme reads the items' priority. |
| 0.2.6 | Windows: Show in Folder after sharing a saved, unedited document selects the document in its own folder rather than the staged copy (#265, PR #298). Any other share is a temporary copy, and the notice says so. libs-sharing cbc6726: one share panel at a time, and Share again brings it forward (PR #301). The AppImage starts its own bundled pasteboard server, so Copy and Share work on a host that has GNUstep installed (#302). |

### Where it differs from the design

- **Menu.** File > Share has "Share as <format>...", an "Email as" submenu
  (the four formats, plus "In the Message"), Copy Rendered, Copy for Slack
  and Show File in Folder. The last choice is remembered for each
  destination: the sheet's format, the email format and the menu's format
  (`OMDShareLastSheetChoice`, `OMDShareLastEmailChoice`,
  `OMDShareLastFormat`). These are app defaults, with no control in
  Preferences. Copy as Markdown stays in the preview's context menu, not
  in the Share menu. ODT and RTF stay
  under File > Export, as planned.
- **Not in the design, but shipped:** sharing just the selection
  (`OMDShareSelection`), the `.zip` with the document's local images
  (`OMDShareBundle`), and the checks before sending (`OMDShareChecks`). The
  last two were planned for milestone 2 and arrived in 0.2.3.
- **The library is danjboyd/libs-sharing.** The app compiles it in from
  `third_party/libs-sharing` (copied by `tools/vendor/vendor-libs-sharing.sh`,
  not edited there), so the packages need nothing new. It doesn't
  subclass: it installs its methods into libs-gui's existing
  `NSSharingService*` classes when it loads (`GSSharingInstall()`), so Cocoa
  code runs unchanged.
  - Plug-ins are `.sharingservice` bundles in `Library/SharingServices`, or
    are registered with `GSSharingRegisterProvider()`.
  - Built-in services: Email, Copy, Save a Copy, Show in Folder and Open
    With. **Send to Phone** (KDE Connect / GSConnect) isn't built.
  - The sheet's accessory view (`-setAccessoryView:`, a GNUstep extension)
    holds the app's format switcher.
- **Windows.** The app's Windows presenter stayed in the app. It shows the
  Windows share sheet and uses MAPI for email. libs-sharing's Windows code
  (`GSSharingWin32.m`) backs its own sheet where Windows has none, and its
  Open With (`SHOpenWithDialog`). The libs-sharing README still calls the
  Windows backend "the next part", which is out of date.
- **macOS.** Share uses Apple's `NSSharingServicePicker`, as planned.
  - Email as goes through `OMDShareMail`: a Mail draft with the document as
    the body or as an attachment. With another default mail app, a draft
    opens and the notice offers the file.
  - rclone is a custom `NSSharingService` added through the picker's
    delegate (`OMDShareRcloneMac`).
- **Flatpak.** It shares through the desktop portals (email, OpenURI,
  documents) and offers no rclone. Email to a mail app that the email
  portal doesn't know gets a draft plus the "attach this file" notice.
- **Drag-out.** On Linux the sheet's file icon drags the file out as
  `text/uri-list` into browsers, mail apps and the file manager. Windows
  has no drag-out, because libs-back's win32 backend has no OLE drag and
  drop (#213).

### Open for 0.2.7

- #304 (Linux): the Share panel's Show in Folder selects the staged copy
  for a share of the saved document. PR #311 fixes it the way #298 did on
  Windows. It waits for 0.2.6 final.
- Show in Folder chooses the document only when its extension is
  lower-case `md`. `.markdown`, `.MD`, `.mdown`, and `.TXT` in plain-text
  mode still get the staged copy. Markdown Viewer Windows has the
  case-insensitive check in c921369, which isn't in #311.
- libs-sharing#26 (Windows 11): Esc in Open With's chooser closes the whole
  sheet, because `SHOpenWithDialog` returns `S_OK`.

### Still open, not scheduled

- #177 (macOS): a by-eye check of pasting Copy Rendered and Copy for Slack
  into Mail, Teams and Slack. It needs Dan's Mac and his Teams and Slack.
  If Slack shows Copy for Slack's `*bold*` as typed, the follow-up adds an
  HTML version.
- #198: rclone links have only been made with a stand-in, never with a
  real remote. The first real OneDrive link should confirm the
  organisation-only scope.
- #197: GNOME Online Accounts links haven't been started. The spike's
  risks below still apply (tenant consent, token scopes, the Flatpak).
- #213 (Windows): dragging a file out needs OLE drag and drop in libs-back
  win32. That is a GNUstep change and goes through
  `docs/UPSTREAM_POLICY.md`.
- Upstream: libs-sharing hasn't been offered to libs-gui. Offering it needs
  Dan's sign-off under `docs/UPSTREAM_POLICY.md`.

## Goals

- One gesture, no Save panel, in the common case.
- Use what each platform already does well: the macOS share sheet, the
  Windows share sheet, the desktop's mail client and online accounts on
  Linux.
- Treat pasting as a first-class way to share (short documents into a Teams
  or Slack chat), not only attachments.
- Follow the UI rules in AGENTS.md: standard controls, system colours, no
  theme detection, nothing in Preferences.

Not goals: our own cloud service, our own sign-in screens, a share target
for other apps to send *into* the viewer.

## What the user sees

A Share toolbar item (the `share-symbolic` icon; on macOS an
`NSSharingServicePickerToolbarItem`) and a File > Share submenu with the
same items:

```
Share >
  Share as PDF...
  Share as Word Document...
  Share as Markdown File...
  Share as HTML...
  ---
  Email...                       (attachment in the last-used format)
  ---
  Copy Rendered                  (rich text: Teams, Outlook, email bodies)
  Copy for Slack                 (milestone 2)
  Copy as Markdown               (exists today)
  ---
  Show File in Folder
```

- "Share as <format>" exports the current buffer to a temporary file and
  opens the platform's picker with that file.
- The last-used format is remembered (an ordinary app default, not a
  Preferences control) and its item is listed first.
- What is shared is what is on screen, including unsaved edits. No "save
  first?" prompt.
- File names come from the document: `Q3 Plan.pdf`, never `export-7f3a.pdf`.
  Temporary files go in a per-launch directory under the app's temp
  directory (0700). Nothing is deleted when the picker returns: AirDrop,
  Messages and Mail read the file seconds later. Directories of earlier
  launches are swept at the next launch.
- ODT and RTF stay under File > Export; the Share menu lists the formats
  people send.

### When a step can't happen directly

When the destination can't take the file (a webmail `mailto:` handler, Teams
or Slack on Linux), the share still does as much as it can, then shows a
small notice drawn in tooltip colours:

> Your email app can't receive attachments directly. "Q3 Plan.pdf" is ready:
> [file icon, draggable] - Copy File - Show in Folder

The draggable icon depends on file drags leaving the app as `text/uri-list`
(Linux) or `CF_HDROP` (Windows); see the drag spike below. Show in Folder
is always there as the fallback.

### Checks before sending (milestone 2)

- A Markdown file that links local images or files (`./img/a.png`) warns:
  "This document uses 3 local images your colleague won't have. Share as
  PDF, or share a .zip with the images?"
- Links to local paths (`file:///home/...`) are flagged, since they leak the
  sender's paths and don't open for the reader.
- Math and Mermaid only arrive rendered in PDF, HTML and Word; sharing a
  `.md` of a document with either suggests PDF.

## Per platform

| | Pick a destination | Email with attachment | Paste | Show file |
|---|---|---|---|---|
| macOS | `NSSharingServicePicker` (Mail, Messages, AirDrop, Notes, installed apps' extensions) | Mail via the picker (rich body possible); another default client gets `mailto:` + the notice | `public.html` + `public.rtf` on the pasteboard | `NSWorkspace activateFileViewerSelectingURLs:` |
| Windows | Windows share sheet (`IDataTransferManagerInterop::ShowShareUIForWindow`) | `MAPISendMail` (classic Outlook, Thunderbird); webmail or no MAPI -> notice | `CF_HTML` + RTF | `SHOpenFolderAndSelectItems` |
| Linux | our picker panel (milestone 1 in the app, milestone 2 in the library) | email portal (`org.freedesktop.portal.Email`), else `xdg-email --attach`; a client that can't attach (webmail) -> notice | `text/html` + RTF; file as `text/uri-list` + `x-special/gnome-copied-files` | `org.freedesktop.FileManager1.ShowItems`, else open the folder |

Email clients that take attachments are a capability check of the
`mailto:` handler (Evolution, Thunderbird, KMail, Outlook classic), not a
theme or desktop check.

## Architecture in the app (milestone 1)

New files in `ObjcMarkdownViewer/`; every platform's code behind one
protocol so the three agents can work in parallel without touching each
other's files:

- `OMDShareItem` - what is shared: title, format, the exported file URL
  and/or an attributed string. Built by `OMDShareExporter`.
- `OMDShareExporter` - exports the current buffer to a temp file in a given
  format with no panel. It reuses the existing paths:
  `-exportDocumentAsPDFToPath:` and
  `OMDDocumentConverter -exportMarkdown:toPath:resourceDirectory:error:`
  (Pandoc). The Export menu's panel code then calls this too.
- `OMDShareController` - builds the Share menu and toolbar item, remembers
  the last format, runs export -> presenter, and shows the notice.
- `OMDSharePresenter` (protocol) - `-presentShareItem:fromView:` and
  `-emailShareItem:`, `-showShareItemInFolder:`, `-copyFileOfShareItem:`.
  Implementations, one file each:
  - `OMDSharePresenterMac.m` (`#if !defined(GNUSTEP)`)
  - `OMDSharePresenterWindows.m` (`#if defined(_WIN32)`)
  - `OMDSharePresenterLinux.m` (GNUstep, not Windows)
- `OMDShareNotice` - the fallback notice: a small panel with standard
  controls (an `NSImageView` drag source, two buttons).
- `OMDRichPasteboard` - puts HTML + RTF of the rendered document on the
  pasteboard for Copy Rendered.

The Linux agent lands this skeleton first (with stub presenters), so the
macOS and Windows agents build their presenters against it.

### Skeleton API

```objc
typedef NS_ENUM(NSInteger, OMDShareFormat) {
    OMDShareFormatPDF = 0,
    OMDShareFormatWord,      /* .docx via Pandoc */
    OMDShareFormatMarkdown,
    OMDShareFormatHTML
};

/* OMDShareItem.h */
@interface OMDShareItem : NSObject
@property (nonatomic, readonly, copy) NSString *title;        /* "Q3 Plan" */
@property (nonatomic, readonly) OMDShareFormat format;
@property (nonatomic, readonly, copy) NSURL *fileURL;         /* exported file */
@property (nonatomic, readonly, copy) NSAttributedString *renderedText; /* may be nil */
@end

/* OMDShareExporter.h */
@interface OMDShareExporter : NSObject
+ (NSString *)fileExtensionForFormat:(OMDShareFormat)format;
+ (NSString *)displayNameForFormat:(OMDShareFormat)format;   /* "PDF", "Word Document" */
+ (NSString *)launchTemporaryDirectory;                       /* created 0700 on first use */
+ (void)sweepStaleTemporaryDirectories;                       /* called at launch */
- (instancetype)initWithWindowController:(OMDWindowController *)controller;
/* Exports the current buffer (unsaved edits included). Never deletes the file. */
- (OMDShareItem *)shareItemForFormat:(OMDShareFormat)format error:(NSError **)error;
@end

/* OMDSharePresenter.h */
@protocol OMDSharePresenter <NSObject>
- (void)presentShareItem:(OMDShareItem *)item fromView:(NSView *)view;
- (void)emailShareItem:(OMDShareItem *)item;
- (void)showShareItemInFolder:(OMDShareItem *)item;
- (void)copyFileOfShareItem:(OMDShareItem *)item;
@optional
/* A platform's own toolbar item (macOS: NSSharingServicePickerToolbarItem).
   The provider exports lazily, when the picker opens, in the last-used
   format. Without this, the controller makes an NSMenuToolbarItem with
   share-symbolic and the Share menu. */
- (NSToolbarItem *)shareToolbarItemWithIdentifier:(NSString *)identifier
                                     itemProvider:(OMDShareItem *(^)(void))provider;
@end
id<OMDSharePresenter> OMDCreatePlatformSharePresenter(void);  /* one per platform file */

/* OMDShareNotice.h: the fallback notice, standard controls, tooltip colours */
@interface OMDShareNotice : NSObject
/* message: "Your email app can't receive attachments directly."
   Shows the file (drag source where supported), Copy File and Show in Folder,
   which call back into the presenter. Non-modal; closes on Escape or when
   the window it is attached to closes. */
+ (void)showNoticeWithMessage:(NSString *)message
                    shareItem:(OMDShareItem *)item
                    presenter:(id<OMDSharePresenter>)presenter
                    forWindow:(NSWindow *)window;
@end
```

File > Share is our own submenu on every platform (the same items
everywhere); the toolbar item is the platform's where it has one.

## The library (milestone 2): a GNUstep share sheet

`libs-gui` already ships Apple's `NSSharingService.h` and
`NSSharingServicePickerToolbarItem.h`, but the implementation is stubs (the
toolbar item returns `nil`). The library implements Apple's API rather than
inventing one:

- Same API on every platform: the viewer's share code is identical on
  macOS (AppKit) and GNUstep; ported Cocoa apps that use a share sheet just
  work.
- Starts as its own repository (working name `libs-sharing`), and is offered
  to `libs-gui` once proven, under `docs/UPSTREAM_POLICY.md`.

Pieces:

- `NSSharingService` - one destination: title, image, `canPerformWithItems:`,
  `performWithItems:`, delegate callbacks.
- `NSSharingServicePicker` - the sheet. Standard controls only (a panel with
  an icon list and buttons), so Adwaita, WinUITheme and the default theme
  each draw it; a theme may supply its own picker class.
- Service plug-ins: bundles in `Library/SharingServices` of every GNUstep
  domain, so third parties add destinations without patching the library.
  Built in:
  - Email (portal -> `xdg-email` -> notice; MAPI on Windows)
  - Copy (file, HTML, RTF)
  - Show in Folder
  - Save a Copy...
  - Send to Phone (KDE Connect / GSConnect over D-Bus, when present)
  - Open With... (apps whose desktop entries take files)
- Items say what they are (a file URL, an attributed string); each service
  asks for the form it wants. That is how "Copy for Slack" and "Copy
  Rendered" fit without the app knowing about Slack.
- Windows backend: the same API over the Windows share sheet and MAPI,
  replacing the app's Windows presenter.

### GNOME Online Accounts (milestone 3)

- Discover accounts on the session bus (`org.gnome.OnlineAccounts`) that
  offer files: Google, Microsoft 365 (OneDrive), Nextcloud/ownCloud.
- Upload: a GIO copy to the account's GVfs location. No HTTP code of ours.
- Share link: GOA gives a short-lived OAuth token on request; one API call
  per provider (Microsoft Graph `createLink`, Drive permissions + link,
  Nextcloud OCS share). Tokens are never stored.
- Picker items per account: "Upload to OneDrive (work)", "Share Link via
  OneDrive (work)". No accounts -> "Add an Online Account..." opens GNOME
  Settings. No GOA on the bus -> no items (capability check, not desktop
  name).
- Link scope: organisation-only for work accounts where the provider allows
  it; the notice always says who can open the link.
- Sharing the same document again updates the same cloud file.
- Risks to settle in the spike: GOA's Microsoft provider signs in as GNOME's
  app, which company tenants may block (test Dan's tenant first); token
  scopes may not allow creating links; the Flatpak needs
  `--talk-name=org.gnome.OnlineAccounts`, which exposes all tokens, so
  cloud links may stay out of the Flatpak.

### rclone (milestone 3)

- Shown only when `rclone` is on the `PATH` and `rclone listremotes` lists
  remotes. No setup UI and no "install rclone" prompts.
- Upload with `rclone copyto`, link with `rclone link`, with the safest
  scope each backend offers (for OneDrive
  `--onedrive-link-scope organization`). Google Drive links are "anyone
  with the link"; the notice says so.
- A timeout, progress and Cancel; rclone's error text shown on failure
  (e.g. an expired token -> "run rclone config reconnect <remote>:").
- An encrypted rclone config asks for its password for that run only.
- Not in the Flatpak (it would need a sandbox escape); available in the
  AppImage, the MSI and on macOS, where it is added to Apple's picker as a
  custom `NSSharingService` through the picker delegate.
- The picker groups items by source ("Online Accounts", "rclone"), so the
  same drive seen twice is not confusing.

## Security and privacy

- No credentials stored by the app or the library, ever.
- Temp exports are user-only (0700 directory) and cleaned up.
- External programs (`xdg-email`, `rclone`) get arguments as an argv
  array, never a shell string.
- Every link-producing action states who can open the link.

## Testing

- Unit tests (tools-xctest / XCTest): exporter naming and temp cleanup,
  format -> extension map, local-image/link detection, Slack conversion,
  `mailto:` handler capability parsing, rclone output parsing.
- By eye, in the private `tools/dev/` session: the picker and notice under
  the default theme and Adwaita; WinUITheme on Windows; light and dark on
  macOS.
- Release checks run on the CI packages, as for every release: AppImage,
  Flatpak, MSI, dmg.

## Milestones and who does what

Three agents: **Linux** (this repository's Linux session), **macOS** and
**Windows**. Each item is a GitHub sub-issue of the tracking issue; one PR
per item.

### Milestone 1: Share in the app

| Owner | Work |
|---|---|
| Linux | Skeleton first: `OMDShareItem`, `OMDShareExporter` (panel-free export, naming, temp cleanup), `OMDShareController` (menu, toolbar item, last format), `OMDSharePresenter` protocol with stubs, `share-symbolic` icon. Then Copy Rendered (`OMDRichPasteboard`), the notice, the Linux presenter (picker panel, email portal / `xdg-email` / notice, Show in Folder, Copy File). The drag-out spike on X11 and Wayland. |
| macOS | `OMDSharePresenterMac`: `NSSharingServicePicker` and its toolbar item, Mail with a rich body, `mailto:` + notice for other default clients, Copy Rendered checked against Mail, Teams and Slack on macOS. |
| Windows | `OMDSharePresenterWindows`: the Windows share sheet from the GNUstep win32 app (feasibility first), `MAPISendMail` with the notice fallback (check new Outlook), `SHOpenFolderAndSelectItems`, `CF_HTML`/RTF and `CF_HDROP` on the clipboard, the drag-out spike on win32. |

Exit: Share works from the toolbar and menu on all three platforms in PDF,
Word, Markdown and HTML; Copy Rendered pastes well into Teams and Outlook.
Then Dan decides: cut a release, or go on to milestone 2.

### Milestone 2: polish and the library

| Owner | Work |
|---|---|
| Linux | Create the library: `NSSharingService` / `NSSharingServicePicker` for GNUstep, plug-in loading, built-in services moved out of the app; the draggable file in the notice (if the spike passed or after a libs-back fix); file-to-clipboard. |
| macOS | Copy for Slack (a converter in the ObjcMarkdown library with tests); local image/link checks and the `.zip` bundle (shared logic, used by every platform). |
| Windows | Move the Windows presenter into the library's Windows backend; MSI packaging of the library and its plug-ins. |

### Milestone 3: cloud links

| Owner | Work |
|---|---|
| Linux | The GOA spike (Dan's Microsoft 365 tenant, a Google account, scopes, Flatpak), then the GOA plug-in. The rclone plug-in in the library. |
| macOS | rclone as a custom `NSSharingService` in Apple's picker. |
| Windows | rclone in the library on Windows; the Windows check of both plug-ins where they apply. |

## Open questions

Settled by what shipped:
- Word or ODT: Share lists Word only, and ODT stays under File > Export.
- Paste or attach for Teams: the menu leaves it to the user, and Share
  suggests neither from the document's length.
- The library's name and home: danjboyd/libs-sharing.

Still open:
- When to offer libs-sharing to GNUstep (libs-gui), and in what form. Its
  method-installing design was chosen so the code can move into libs-gui
  later. Dan decides, under `docs/UPSTREAM_POLICY.md`.
- Whether to build the remaining library services (Send to Phone) or drop
  them from the plan.
- GNOME Online Accounts (#197): whether it's still wanted now that rclone
  links ship.
