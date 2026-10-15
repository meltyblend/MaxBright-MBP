#!/usr/bin/env bash
# Installs the latest MaxBright release, adds the `maxbright` command and starts the app:
#   curl -fsSL https://raw.githubusercontent.com/meltyblend/MaxBright-MBP/main/install.sh | bash
# Running it again updates MaxBright. To remove it:
#   curl -fsSL https://raw.githubusercontent.com/meltyblend/MaxBright-MBP/main/install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="meltyblend/MaxBright-MBP"
BUNDLE_ID="io.github.maxbright"
BIN_DIRS=(/usr/local/bin /opt/homebrew/bin "$HOME/.local/bin")

fail() {
    echo "MaxBright: $*" >&2
    exit 1
}

# Quitting restores the display: macOS resets the gamma table when the process exits.
quit_running_app() {
    if pgrep -x MaxBright >/dev/null; then
        pkill -x MaxBright || true
        sleep 1
    fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
    quit_running_app
    rm -rf /Applications/MaxBright.app "$HOME/Applications/MaxBright.app"
    for dir in "${BIN_DIRS[@]}"; do
        link="$dir/maxbright"
        if [[ -L "$link" && "$(readlink "$link")" == */MaxBright.app/* ]]; then rm -f "$link"; fi
    done
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "MaxBright has been uninstalled."
    exit 0
fi

[[ "$(uname -s)" == Darwin ]] || fail "MaxBright only runs on macOS."
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]] || fail "MaxBright needs an Apple silicon Mac."
(( $(sw_vers -productVersion | cut -d. -f1) >= 13 )) || fail "MaxBright needs macOS 13 Ventura or later."

APP_DIR=/Applications
[[ -w "$APP_DIR" ]] || APP_DIR="$HOME/Applications"
APP="$APP_DIR/MaxBright.app"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading MaxBright…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/MaxBright.zip" -o "$tmp/MaxBright.zip" \
    || fail "the download failed. Check your connection and try again."
ditto -x -k "$tmp/MaxBright.zip" "$tmp"
[[ -d "$tmp/MaxBright.app" ]] || fail "the download didn't contain MaxBright.app."

quit_running_app
mkdir -p "$APP_DIR"
rm -rf "$APP"
ditto "$tmp/MaxBright.app" "$APP"
# curl doesn't mark downloads as quarantined, but clear the flag in case the zip arrived some other way, since
# MaxBright isn't notarized and Gatekeeper would refuse to open it.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
# Each release has a new ad-hoc signature, so an Accessibility grant for an earlier version no longer matches.
# Clear it so the new version can ask again.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

linked=""
for dir in "${BIN_DIRS[@]}"; do
    if [[ -d "$dir" && -w "$dir" && ":$PATH:" == *":$dir:"* ]]; then
        ln -sf "$APP/Contents/Resources/maxbright" "$dir/maxbright"
        linked="$dir/maxbright"
        break
    fi
done

open "$APP"

echo
echo "MaxBright is installed in $APP_DIR and running in the menu bar (the sun icon)."
if [[ -n "$linked" ]]; then
    echo "Control it from the terminal with \`maxbright\`. Try \`maxbright --help\`."
else
    echo "To use the maxbright command, link it into a folder on your PATH:"
    echo "  ln -s \"$APP/Contents/Resources/maxbright\" /usr/local/bin/maxbright"
fi
echo "To boost with F1/F2 past full brightness, allow MaxBright under"
echo "System Settings › Privacy & Security › Accessibility when it asks."
