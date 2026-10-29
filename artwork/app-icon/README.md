# Native app icon

AppIcon.icon in AnkiApp/AnkiApp is based on the supplied lighAnkios.icon and ankiosDark.icon documents. The original images, scale, positioning, shadow and translucency are retained. The light layer uses opacity 1 normally and 0 in Dark; the dark layer uses opacity 0 normally and 1 in Dark. Mono uses the light silhouette and native system rendering.

The target includes AppIcon.icon as a resource and retains the existing AppIcon build setting and conventional asset catalog. Deployment, bundle ID and signing settings are unchanged.

Validation: Apple native icon compilation and unsigned Release device build pass with Xcode 27.1. The compiled asset catalog includes Default, Dark and Tint icon resources. IPA 0.2.3 (build 5) has minimum iOS 26.0, unchanged bundle identifier, no code signature or provisioning profile, and passes ZIP integrity verification. Physical device appearance and installation remain unverified.

Build source: upstream Anki tag 26.05, commit e64c6b1aee3e8d668fb8bbe084beada8e070d985, including core/desktop translation submodules. Register ios/rsbridge-ios in the workspace, run gen-proto.sh and build-xcframework.sh, then build Release for generic iOS with CODE_SIGNING_ALLOWED=NO. Package the app under Payload/ using ZIP. The framework build script pins the native deployment minimum to 26.0 unless explicitly overridden.
