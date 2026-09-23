#!/bin/sh
set -eu

notary_profile="${NOTARY_PROFILE:-Emojichao-Notary}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppInfo.plist)"
app_path=".build/Emojichao.app"
dist_dir="dist"
archive_path="$dist_dir/Emojichao-$version.zip"
checksum_path="$archive_path.sha256"

mkdir -p "$dist_dir"
rm -f "$archive_path" "$checksum_path"

sh build-app.sh release

# Notarytool accepts a ZIP, but the ticket is stapled to the app before the
# final archive is produced so Gatekeeper can validate it offline as well.
ditto -c -k --keepParent "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"

rm -f "$archive_path"
ditto -c -k --keepParent "$app_path" "$archive_path"
shasum -a 256 "$archive_path" > "$checksum_path"

echo "Release ready: $archive_path"
echo "Checksum: $checksum_path"
