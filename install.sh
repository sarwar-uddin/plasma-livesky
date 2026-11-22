#!/bin/sh
# Install Live Sky and make it the lock screen. Safe to re-run.
set -e
cd "$(dirname "$0")"
kpackagetool6 -t Plasma/Wallpaper -i package 2>/dev/null || kpackagetool6 -t Plasma/Wallpaper -u package
install -Dm755 tools/livesky-fetch "$HOME/.local/bin/livesky-fetch"
install -Dm644 systemd/livesky-fetch.service "$HOME/.config/systemd/user/livesky-fetch.service"
install -Dm644 systemd/livesky-fetch.timer "$HOME/.config/systemd/user/livesky-fetch.timer"
install -Dm755 tools/livesky-planes "$HOME/.local/bin/livesky-planes"
install -Dm644 systemd/livesky-planes.service "$HOME/.config/systemd/user/livesky-planes.service"
systemctl --user daemon-reload
systemctl --user enable --now livesky-fetch.timer
systemctl --user enable --now livesky-planes.service
systemctl --user restart livesky-planes.service
cp -n "$HOME/.config/kscreenlockerrc" "$HOME/.config/kscreenlockerrc.before-livesky" 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin com.github.sarwaruddin.livesky
# the stock lock screen clock would duplicate ours: hide it
kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key alwaysShowClock false
"$HOME/.local/bin/livesky-fetch" || true
echo "Live Sky is the lock screen. Preview: /usr/lib/kscreenlocker_greet --testing"
