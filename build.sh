#!/usr/bin/env bash
# Builds MaxBright.app into ./build. Pass "install" to also copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MaxBright"

APP="build/MaxBright.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MaxBright"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x MaxBright 2>/dev/null && sleep 1 || true
    rm -rf /Applications/MaxBright.app
    ditto "$APP" /Applications/MaxBright.app
    # Ad-hoc signed builds get a new identity each time, so an earlier Accessibility grant no longer matches.
    # Clear it so the new build can ask again.
    tccutil reset Accessibility io.github.maxbright >/dev/null 2>&1 || true
    open /Applications/MaxBright.app
    echo "Installed to /Applications/MaxBright.app"
fi
