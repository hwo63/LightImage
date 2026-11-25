#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

app="$PWD/dist/LightImage.app"
plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
stamp=$(/usr/libexec/PlistBuddy -c 'Print :LightImageBuildStamp' "$plist")
architecture=$(uname -m)
name="LightImage-$version-$stamp-macOS-$architecture"
stage=$(mktemp -d "$PWD/.build/release-package.XXXXXX")
release="$PWD/dist/releases/$version"
mkdir -p "$stage/disk" "$release"

ditto "$app" "$stage/disk/LightImage.app"
ln -s /Applications "$stage/disk/Applications"
hdiutil create -quiet -format UDZO -volname LightImage -srcfolder "$stage/disk" "$stage/$name.dmg"
hdiutil verify -quiet "$stage/$name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$name.app.zip"

mv "$stage/$name.dmg" "$stage/$name.app.zip" "$release/"
echo "Packaged: $release/$name.dmg"
echo "Packaged: $release/$name.app.zip"
