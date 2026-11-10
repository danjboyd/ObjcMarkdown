#!/usr/bin/env bash
# Review-only command list. Run ONLY in a separately approved disposable guest.
# This script inventories capabilities; it opens no display and changes no file.
set -euo pipefail
test -f /var/lib/oracletestvms/debian13-lease-configured
grep -qx 'VERSION_ID="13"' /etc/os-release
systemd-detect-virt --vm
for name in Xorg xauth xwd xprop xwininfo xdpyinfo zenity dbus-run-session gnome-shell gsettings python3 dpkg-deb readelf; do
  command -v "$name"
done
dpkg-query -W -f='${Package} ${Version}\n' xserver-common xauth x11-apps x11-utils libx11-6 libxfont2 libpixman-1-0 libaudit1 libgl1 libnettle8t64 libunwind8
ldconfig -p
if command -v Xvfb; then
  sha256sum "$(command -v Xvfb)"
else
  printf '%s\n' 'PROVISIONING_REQUIRED: pinned guest-private Xvfb data extraction; no automatic install'
fi
