#!/bin/sh
set -eu

mode="${1:-debug}"
case "$mode" in
    debug|release) ;;
    *) echo "Usage: sh build-app.sh [debug|release]" >&2; exit 2 ;;
esac

signing_identity=""
if [ "$mode" = release ]; then
    signing_identity="$(security find-identity -p codesigning -v | awk -F '"' '/"Developer ID Application: / { print $2; exit }')"
    if [ -z "$signing_identity" ]; then
        echo "Release requires a Developer ID Application signing certificate. No app was replaced." >&2
        exit 1
    fi
else
    signing_identity="$(security find-identity -p codesigning -v | awk -F '"' '/"Apple Development: / { print $2; exit }')"
    if [ -z "$signing_identity" ]; then
        echo "WARNING: No Apple Development certificate found. Ad-hoc signing changes app identity on rebuild and can reset Accessibility, Input Monitoring, and Keychain access." >&2
        signing_identity="-"
    fi
fi

if [ "$mode" = release ]; then
    # Build one app for both supported Mac architectures.
    swift build -c release --arch arm64 --arch x86_64
    bin_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c debug
    bin_dir="$(swift build -c debug --show-bin-path)"
fi
app_dir=".build/EmojiShortcut.app"
staging_dir=".build/EmojiShortcut-next.app"
rm -rf "$staging_dir"
mkdir -p "$staging_dir/Contents/MacOS" "$staging_dir/Contents/Resources"
cp "$bin_dir/EmojiShortcut" "$staging_dir/Contents/MacOS/EmojiShortcut"
cp AppInfo.plist "$staging_dir/Contents/Info.plist"
cp -R "$bin_dir/EmojiShortcut_EmojiShortcut.bundle" "$staging_dir/Contents/Resources/"
cp AppSources/EmojiShortcut/Resources/Icons/AppIcon.icns "$staging_dir/Contents/Resources/AppIcon.icns"
if [ "$mode" = release ]; then
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$staging_dir"
else
    codesign --force --deep --sign "$signing_identity" "$staging_dir"
fi
codesign --verify --deep --strict "$staging_dir"
rm -rf "$app_dir"
mv "$staging_dir" "$app_dir"

echo "Built $app_dir ($mode; signing identity: $signing_identity)"
echo "Run with: open $app_dir"
