#!/bin/sh
# MarkdownViewer's launcher in the Flatpak. The Adwaita theme is the
# default until the user picks another in Preferences (which writes the
# same GSTheme default).
. /app/share/GNUstep/Makefiles/GNUstep.sh
if ! defaults read NSGlobalDomain GSTheme >/dev/null 2>&1; then
    defaults write NSGlobalDomain GSTheme Adwaita
fi
exec /app/lib/GNUstep/Applications/MarkdownViewer.app/MarkdownViewer "$@"
