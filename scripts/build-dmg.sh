#!/bin/zsh

set -euo pipefail

root_dir=${0:A:h:h}
app_bundle=${1:-"$root_dir/.build/CubismMetal.app"}
destination=${2:-"$root_dir/.build/CubismMetal.dmg"}

if [[ ! -d "$app_bundle" ]]; then
  print -u2 "CubismMetal app bundle not found: $app_bundle"
  print -u2 "Build it first with: /bin/zsh scripts/build-app.sh \"$app_bundle\""
  exit 2
fi

if [[ -e "$destination" ]]; then
  print -u2 "refusing to overwrite existing disk image: $destination"
  exit 2
fi

mkdir -p "${destination:h}"
hdiutil create -format UDZO -volname CubismMetal -srcfolder "$app_bundle" "$destination"

print "CubismMetal disk image: $destination"
