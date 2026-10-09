#!/bin/sh
# MarkdownViewer's launcher in the Flatpak. The Adwaita theme is the
# default until the user picks another in Preferences (which writes the
# same GSTheme default).
. /app/share/GNUstep/Makefiles/GNUstep.sh
if ! defaults read NSGlobalDomain GSTheme >/dev/null 2>&1; then
    defaults write NSGlobalDomain GSTheme Adwaita
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
