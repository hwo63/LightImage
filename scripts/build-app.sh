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
cp "$bin_dir/LightImageInstaller" "$app/Contents/MacOS/LightImageInstaller"
cp Resources/Info.plist "$app/Contents/Info.plist"
plist="$app/Contents/Info.plist"
build_epoch=${LIGHTIMAGE_BUILD_EPOCH:-$(date +%s)}
read -r bundle_build display_build <<< "$(TZ=Asia/Ho_Chi_Minh date -r "$build_epoch" '+%Y%m%d.%H%M%S %d%m.%H%M%S')"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $bundle_build" "$plist"
/usr/libexec/PlistBuddy -c "Add :LightImageBuildStamp string $display_build" "$plist"
if [[ -n "${LIGHTIMAGE_UPDATE_PUBLIC_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :LightImageUpdatePublicKey string $LIGHTIMAGE_UPDATE_PUBLIC_KEY" "$plist"
fi
cp LICENSE "$app/Contents/Resources/LICENSE"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns "$PWD/.build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp -R Samples "$app/Contents/Resources/"
codesign --force --sign - "$app/Contents/MacOS/LightImageInstaller"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
output_dir=${LIGHTIMAGE_OUTPUT_DIR:-"$PWD/dist"}
final="$output_dir/LightImage.app"
mkdir -p "$output_dir"
# Rename the old bundle without modifying its executable: a running instance stays intact.
if [[ -d "$final" ]]; then mv "$final" "$stage/Previous-LightImage.app"; fi
if ! mv "$app" "$final"; then
  if [[ -d "$stage/Previous-LightImage.app" ]]; then mv "$stage/Previous-LightImage.app" "$final"; fi
  exit 1
fi
echo "Built: $final"
