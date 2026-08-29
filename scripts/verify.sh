#!/bin/zsh

set -euo pipefail

root_dir=${0:A:h:h}
cd "$root_dir"

if (( $# != 1 )); then
  print -u2 "usage: scripts/verify.sh <tests|build|samples|xcode|xcode-tests>"
  exit 64
fi

case "$1" in
  tests)
    set +e
    test_output=$(swift test 2>&1)
    test_status=$?
    set -e

    if (( test_status != 0 )); then
      if [[ "$test_output" != *"unable to resolve module dependency: 'XCTest'"* ]]; then
        print -u2 -r -- "$test_output"
        exit "$test_status"
      fi
      print -u2 "XCTest is unavailable in the active developer tools; running the package-native verifier instead."
      swift run CubismMetalVerification
    fi
    print "cubism-metal tests passed"
    ;;
  build)
    swift build -c release
    print "cubism-metal build passed"
    ;;
  samples)
    samples_directory="$root_dir/Samples"
    if [[ ! -d "$samples_directory" && -d "$root_dir/samples" ]]; then
      samples_directory="$root_dir/samples"
    fi
    if [[ ! -d "$samples_directory" ]]; then
      print -u2 "Samples directory is missing: $root_dir/Samples"
      exit 2
    fi

    model_paths=("${(@f)$(find "$samples_directory" -type f -name '*.model3.json' -print)}")
    if (( ${#model_paths[@]} == 0 )); then
      print -u2 "no .model3.json files found under $samples_directory"
      exit 2
    fi

    swift build
    for model_path in "${model_paths[@]}"; do
      .build/debug/CubismMetal --validate "$model_path"
    done
    print "cubism-metal samples passed"
    ;;
  xcode)
    xcode_developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
    if [[ ! -d "$xcode_developer_dir" ]]; then
      print -u2 "Xcode developer directory is unavailable: $xcode_developer_dir"
      exit 2
    fi

    xcode_derived_data=$(mktemp -d)
    DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
      -project CubismMetal.xcodeproj \
      -scheme CubismMetal \
      -configuration Debug \
      -derivedDataPath "$xcode_derived_data" \
      CODE_SIGNING_ALLOWED=NO build
    "$xcode_derived_data/Build/Products/Debug/CubismMetal.app/Contents/MacOS/CubismMetal" --validate-renderer
    print "cubism-metal xcode build passed"
    ;;
  xcode-tests)
    xcode_developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
    if [[ ! -d "$xcode_developer_dir" ]]; then
      print -u2 "Xcode developer directory is unavailable: $xcode_developer_dir"
      exit 2
    fi

    xcode_derived_data=$(mktemp -d)
    DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
      -project CubismMetal.xcodeproj \
      -scheme CubismMetal \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$xcode_derived_data" \
      CODE_SIGNING_ALLOWED=NO test
    print "cubism-metal xcode tests passed"
    ;;
  *)
    print -u2 "unknown verification target: $1"
    exit 64
    ;;
esac
