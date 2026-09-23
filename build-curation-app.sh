#!/bin/sh
set -eu

swift build -c debug --product EmojiCuration
app_dir=".build/EmojiCuration.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$(swift build -c debug --show-bin-path)/EmojiCuration" "$app_dir/Contents/MacOS/EmojiCuration"
cp AppInfo.plist "$app_dir/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "Emojichao 絵文字仕分け" "$app_dir/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "EmojiCuration" "$app_dir/Contents/Info.plist"
plutil -replace CFBundleName -string "Emojichao Curation" "$app_dir/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "com.emojichao.curation" "$app_dir/Contents/Info.plist"
plutil -replace LSUIElement -bool false "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
echo "Built $app_dir"
echo "Run with: open $app_dir"
