#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --disable-sandbox --build-system native -c release
bin_dir=$(swift build --disable-sandbox --build-system native -c release --show-bin-path)
stage=$(mktemp -d "$PWD/.build/app-stage.XXXXXX")
app="$stage/LightImage.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/LightImage" "$app/Contents/MacOS/LightImage"
cp Resources/Info.plist "$app/Contents/Info.plist"
plist="$app/Contents/Info.plist"
template_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
read -r year bundle_build display_build <<< "$(TZ=Asia/Ho_Chi_Minh date '+%y %Y%m%d.%H%M%S %d%m.%H%M%S')"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $year.${template_version#*.}" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $bundle_build" "$plist"
/usr/libexec/PlistBuddy -c "Add :LightImageBuildStamp string $display_build" "$plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns "$PWD/.build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp -R Samples "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
final="$PWD/dist/LightImage.app"
mkdir -p "$PWD/dist"
# Rename the old bundle without modifying its executable: a running instance stays intact.
if [[ -d "$final" ]]; then mv "$final" "$stage/Previous-LightImage.app"; fi
if ! mv "$app" "$final"; then
  if [[ -d "$stage/Previous-LightImage.app" ]]; then mv "$stage/Previous-LightImage.app" "$final"; fi
  exit 1
fi
echo "Built: $final"
