#!/bin/sh
# MarkdownViewer's launcher in the Flatpak. The app itself registers the
# Adwaita theme as its default until the user picks another in Preferences.
. /app/share/GNUstep/Makefiles/GNUstep.sh
# The menu button, as the AppImage seeds it, so Preferences shows the same
# value the theme draws (written only when unset).
if ! defaults read MarkdownViewer GnomeThemeMenuStyle >/dev/null 2>&1; then
    defaults write MarkdownViewer GnomeThemeMenuStyle primary
fi
# Shortcuts use Ctrl, as the menus show, not GNUstep's default Alt: the
# Command keys are Control, Control moves to Alt and Alternate to Super.
# Written to the app's domain once, so the user can still change them.
if ! defaults read MarkdownViewer GSFirstCommandKey >/dev/null 2>&1; then
    defaults write MarkdownViewer GSFirstCommandKey Control_L
    defaults write MarkdownViewer GSSecondCommandKey Control_R
    defaults write MarkdownViewer GSFirstControlKey Alt_L
    defaults write MarkdownViewer GSSecondControlKey Alt_R
    defaults write MarkdownViewer GSFirstAlternateKey Super_L
    defaults write MarkdownViewer GSSecondAlternateKey Super_R
fi
exec /app/lib/GNUstep/Applications/MarkdownViewer.app/MarkdownViewer "$@"
