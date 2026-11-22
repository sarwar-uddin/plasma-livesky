#!/bin/sh
# Put the lock screen back the way it was before Live Sky.
set -e
systemctl --user disable --now livesky-fetch.timer livesky-planes.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/livesky-fetch.service" "$HOME/.config/systemd/user/livesky-fetch.timer" "$HOME/.local/bin/livesky-fetch"
rm -f "$HOME/.config/systemd/user/livesky-planes.service" "$HOME/.local/bin/livesky-planes"
rm -rf "$HOME/.cache/livesky"
systemctl --user daemon-reload
if [ -f "$HOME/.config/kscreenlockerrc.before-livesky" ]; then
    cp "$HOME/.config/kscreenlockerrc.before-livesky" "$HOME/.config/kscreenlockerrc"
else
    kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
fi
kpackagetool6 -t Plasma/Wallpaper -r com.github.sarwaruddin.livesky || true
echo "Lock screen restored."
