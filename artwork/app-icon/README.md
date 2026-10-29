# Native app icon

AppIcon.icon in AnkiApp/AnkiApp is based on the supplied lighAnkios.icon and ankiosDark.icon documents. The original images, scale, positioning, shadow and translucency are retained. The light layer uses opacity 1 normally and 0 in Dark; the dark layer uses opacity 0 normally and 1 in Dark. Mono uses the light silhouette and native system rendering.

The target includes AppIcon.icon as a resource and retains the existing AppIcon build setting and conventional asset catalog. Deployment, bundle ID and signing settings are unchanged.

Validation: project plist syntax passes. Apple asset compilation passes. Full unsigned Release build resolves SwiftProtobuf but stops because Anki.xcframework is absent. No replacement IPA has been produced or published. Device appearance and IPA installation are unverified.

To finish: restore the existing Anki.xcframework at repository root (or rebuild it using build-xcframework.sh inside the upstream Anki workspace), then build Release for generic iOS with CODE_SIGNING_ALLOWED=NO. Package the resulting app under Payload/ in a ZIP named Ankios.ipa. Verify no signing identity/provisioning profile is included before publishing a release.
