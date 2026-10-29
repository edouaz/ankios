# App icon integration status

Branch: feat/professional-app-icon. Deployment remains iOS 26.0. Existing AppIcon build settings remain valid; no signing or bundle identifier changes.

The asset catalog contains opaque RGB 1024×1024 default, dark and grayscale tinted PNGs. Approved light/dark references are preserved here, together with transparent 1024×1024 foregrounds for import. Artwork is fitted proportionally inside an 880-pixel square, centered, on an opaque background; no rounded mask is baked in.

## Remaining native artwork work

These foregrounds retain the supplied raster lighting. They are NOT independently editable card, star or highlight layers, and must not be described as a finished native Liquid Glass icon. Accurate vector reconstruction and separation remain outstanding. Do not apply strong extra glass effects to the existing glossy raster.

Icon Composer is installed inside Xcode.app/Contents/Applications. UI import automation did not reliably complete, so no fabricated .icon is supplied.

Manual completion:
1. Create a new Icon Composer document named AppIcon outside the target folder while preparing it.
2. Import foreground-light.png via Add Layer > New Image. Use foreground-dark.png as the Dark appearance image override. Keep image scale and placement identical.
3. Set an opaque pale blue background for Default and navy for Dark. Use Mono preview to assess silhouette and contrast. Start with minimal additional glass on the raster; proper native refraction requires separately reconstructed card surfaces and star cutout.
4. After vector reconstruction, import rear card, front card with star cutout, and optional highlights in that order. Remove baked highlights where native specular effects replace them. Adjust translucency conservatively against white, black and saturated wallpaper previews.
5. Verify Default, Dark, Mono, clear light/dark and tinted previews at small sizes before saving AppIcon.icon.
6. Add the actual saved document to the app target. Keep ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon. Xcode gives the Composer document priority over the matching asset catalog; verify compiled output before deleting any fallback assets.
7. Build and install on an iOS 26 simulator, check Home Screen, Settings and Spotlight, then archive through the existing unsigned IPA process and inspect the app bundle's icon resources.

## Validation

Passed: all three catalog PNGs are RGB, opaque and exactly 1024×1024; catalog appearance entries use dark/tinted luminosity variants. Configuration inspection confirms Debug/Release use AppIcon. No distribution script icon references found. build-xcframework.sh builds the Rust bridge only.

Blocked: Xcode simulator build could not resolve apple/swift-protobuf because network DNS was unavailable; CoreSimulator also reported unavailable services/runtimes. Build, IPA inclusion and device appearance checks have NOT passed. No native Liquid Glass configuration or visual acceptance is claimed.

Apple reference: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
