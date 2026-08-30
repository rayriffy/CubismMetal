#!/bin/zsh

set -euo pipefail

root_dir=${0:A:h:h}
destination=${1:-"$root_dir/.build/CubismMetal.app"}

cd "$root_dir"
if [[ -e "$destination" ]]; then
  print -u2 "refusing to overwrite existing app bundle: $destination"
  exit 2
fi

swift build -c release

product_directory=$(swift build -c release --show-bin-path)
binary_path="$product_directory/CubismMetal"
resource_bundle="$product_directory/CubismMetal_CubismMetalKit.bundle"
icon_file="$root_dir/Assets/CubismMetal.icns"
core_directory="$root_dir/Vendor/CubismCore"
core_library=""
for candidate in libLive2DCubismCore.dylib libLive2DCubismCoreJNI.dylib Live2DCubismCore.dylib; do
  candidate_path="$core_directory/$candidate"
  if [[ -f "$candidate_path" ]]; then
    core_library="$candidate_path"
    break
  fi
done

if [[ ! -d "$resource_bundle" ]]; then
  print -u2 "CubismMetal resource bundle was not built"
  exit 1
fi

if [[ ! -f "$icon_file" ]]; then
  print -u2 "CubismMetal app icon is missing: $icon_file"
  exit 2
fi

if [[ -z "$core_library" ]]; then
  print -u2 "Official Cubism Core is missing from: $core_directory"
  print -u2 "Copy a redistributable Cubism Core dylib from the licensed SDK package into Vendor/CubismCore."
  exit 2
fi

mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
cp "$binary_path" "$destination/Contents/MacOS/CubismMetal"
# SwiftPM's generated Bundle.module resolves target bundles from the app bundle
# root, so keep the target bundle beside Contents rather than moving it under
# Contents/Resources.
ditto "$resource_bundle" "$destination/${resource_bundle:t}"
ditto "$core_directory" "$destination/Contents/Resources/CubismCore"
cp "$icon_file" "$destination/Contents/Resources/CubismMetal.icns"
cp "$root_dir/scripts/CubismMetal.Info.plist" "$destination/Contents/Info.plist"
# Xcode expands these variables while building its product. This standalone
# SwiftPM packager copies the same template, so materialize the values before
# LaunchServices inspects the bundle.
plutil -replace CFBundleDevelopmentRegion -string en "$destination/Contents/Info.plist"
plutil -replace CFBundleExecutable -string CubismMetal "$destination/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.rayriffy.CubismMetal "$destination/Contents/Info.plist"
plutil -replace CFBundleName -string CubismMetal "$destination/Contents/Info.plist"
plutil -replace CFBundleIconFile -string CubismMetal.icns "$destination/Contents/Info.plist"

print "CubismMetal app bundle: $destination"
