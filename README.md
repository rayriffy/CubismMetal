# CubismMetal

CubismMetal is a native macOS viewer for Live2D Cubism models. It opens a
model, plays its bundled motions, and draws the evaluated meshes with Metal.

## Features

- Opens `.model3.json` manifests and `.moc3` files with a sibling manifest.
- Supports the launch picker, Finder open, and Command-O.
- Plays named `.motion3.json` animations. Looping is on by default.
- Draws normal, additive, and multiplicative layers in render order, including
  Cubism clipping masks.
- Targets 60 FPS by default and can target 120 FPS when the display and model
  can sustain it.
- Lets you pan, zoom, reset the canvas, and show a measured FPS overlay.

## Build a local app

```zsh
swift build
/bin/zsh scripts/build-app.sh
/bin/zsh scripts/build-dmg.sh
open .build/CubismMetal.dmg
```

Neither packaging script overwrites an existing output. Pass explicit paths
when you need another bundle or disk image.

GitHub Actions builds an ad-hoc-signed `CubismMetal.dmg` containing the app.
It is not Developer ID-signed or notarized. After extracting the
`CubismMetal-macos` workflow artifact, open that disk image and drag or open
`CubismMetal.app`.

## Run in Xcode

`project.yml` is the XcodeGen source of truth. Regenerate the project after
changing it:

```zsh
xcodegen generate
open -a /Applications/Xcode-beta.app CubismMetal.xcodeproj
```

Choose the **CubismMetal** scheme and **My Mac**, then press Run. Use
Command-U for XCTest.

For a useful 120 FPS measurement, turn off **Metal API Validation** and **GPU
Frame Capture** in Run → Diagnostics, or use a Release build. Those debugging
layers validate every Metal call and can substantially reduce the reported
frame rate on models with many drawables. The **Show FPS counter** option in
the Performance sidebar shows the measured render rate.

## Checks

```zsh
/bin/zsh scripts/verify.sh tests
/bin/zsh scripts/verify.sh build
/bin/zsh scripts/verify.sh samples
```

The sample check validates every `.model3.json` under `Samples/`. OrtLinde
Akasha is the main real-model fixture.

## Current limits

CubismMetal does not use Cubism's high-level Framework renderer. Physics,
pose, expression blending, and Cubism 5 offscreen parts are not implemented.
