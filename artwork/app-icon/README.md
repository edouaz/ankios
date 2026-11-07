# Native app icon

## Current release: 0.2.5 (build 7)

The supplied unsigned IPA declares minimum OS 16.0 and device families 1 and 2
(iPhone and iPad). Its executable has LC_BUILD_VERSION minos 16.0. The bundle
contains legacy AppIcon PNGs and CFBundleIcons entries for both device families.
ZIP integrity and the absence of code signatures/provisioning profiles were
checked for the 0.2.5 publication. Physical-device appearance on iOS/iPadOS 16
has not been verified. Website logos are resized from the conventional light
app icon; screenshots are unchanged.

## Historical icon work (0.2.3)

AppIcon.icon in AnkiApp/AnkiApp is based on the supplied lighAnkios.icon and ankiosDark.icon documents. The original images, scale, positioning, shadow and translucency are retained. The light layer uses opacity 1 normally and 0 in Dark; the dark layer uses opacity 0 normally and 1 in Dark. Mono uses the light silhouette and native system rendering.

The target includes AppIcon.icon as a resource and retains the existing AppIcon build setting and conventional asset catalog. Deployment, bundle ID and signing settings are unchanged.

Validation: Apple native icon compilation and unsigned Release device build pass with Xcode 27.1. The compiled asset catalog includes Default, Dark and Tint icon resources. IPA 0.2.3 (build 5) has minimum iOS 26.0, unchanged bundle identifier, no code signature or provisioning profile, and passes ZIP integrity verification. Physical device appearance and installation remain unverified.

Build source: upstream Anki tag 26.05, commit e64c6b1aee3e8d668fb8bbe084beada8e070d985, including core/desktop translation submodules. Register ios/rsbridge-ios in the workspace, run gen-proto.sh and build-xcframework.sh, then build Release for generic iOS with CODE_SIGNING_ALLOWED=NO. Package the app under Payload/ using ZIP. The framework build script pins the native deployment minimum to 26.0 unless explicitly overridden.

## Required backward compatibility: iOS 16

The icon must remain usable in a build whose deployment target is iOS 16. Liquid Glass is an optional rendering enhancement for iOS 26 and later, not an icon requirement for installation.

With a current Xcode supporting Icon Composer, Apple documents automatic generation of flattened app icon images for older deployment targets. Retain the opaque 1024×1024 conventional AppIcon asset catalog as editable fallback artwork; do not assume the presence of that catalog proves it is selected when the matching Composer document is included. For an older Xcode without Composer support, exclude the .icon resource from that build and use the conventional AppIcon catalog.

Acceptance before claiming iOS 16 icon support: compile the icon resources with minimum deployment 16.0; inspect the generated legacy PNGs and CFBundleIcons; verify Home Screen, Settings and Spotlight on an iOS 16 device or simulator. iOS 16 uses the conventional appearance; native dark/tinted/clear variants are only applicable on OS versions supporting those appearances.

Status: iOS 16 icon compilation and rendering have NOT been validated. The published 0.2.3 IPA still requires iOS 26, and this requirement does not lower the app deployment target or establish full application compatibility with iOS 16.

Apple reference: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
