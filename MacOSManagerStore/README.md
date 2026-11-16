# macOS Manager, App Store edition

This folder is a **separate** SwiftUI app and Swift package. It does not replace the itch.io full edition in the repository root.

## What this edition is for

This edition helps a VoiceOver user **install, upgrade, or downgrade macOS on the Mac itself**. It:

- Reads this Mac's model identifier with `sysctl hw.model` (and shows a friendly Apple model name from the bundled table).
- Lists every macOS version Apple's published compatibility pages say is compatible with that model, and marks the version currently installed.
- Checks whether the selected version can run on this Mac: model, free space against Apple's stated requirement when one exists, memory when Apple states it, upgrade / same version / downgrade, and power from IOKit. The spoken result is "Ready." or "Not ready, here's why."
- Shows a pre-install checklist: Time Machine (opens System Settings), power, internet, restarts, and VoiceOver during installation.
- Offers a button that opens Apple's official installer or Software Update page for the chosen version. Apple handles the download and progress.
- Stays usable while lookup work runs in the background, and explains status in plain words. Text uses Dynamic Type styles and VoiceOver labels.

It does **not** create a bootable USB installer, run `softwareupdate` or `createinstallmedia`, or include a privileged helper. Creating a bootable USB installer is a feature of the full edition, which is a separate product. The App Store UI mentions that in plain language and does **not** include an external purchase link.

## Layout

- `Sources/MacOSManagerStoreCore` is the compatibility table and lookup rules only.
- `Tests/MacOSManagerStoreCoreTests` covers lookup, official download routes, installed-version marking, and readiness (free space, battery, and upgrade or downgrade).
- `App` is the sandboxed SwiftUI interface, with `PrivacyInfo.xcprivacy` set to Data Not Collected.
- `MacOSManagerStore.xcodeproj` builds the unsigned app and the accessibility audit UI tests.
- `APP-STORE-REVIEW-NOTES.md` is Notes for Review.
- `GUIDELINE-4.2-MINIMUM-FUNCTIONALITY.md` records the Guideline 4.2 risk honestly.
- `SOURCES.md` cites the Apple pages behind the bundled table.

## Tests and packaging

On a Mac with Xcode:

```sh
cd MacOSManagerStore
swift test
scripts/package-store-app.sh
```

GitHub Actions workflow `.github/workflows/macos-store-build.yml` runs those unit tests, builds the unsigned universal app (minimum macOS 14), and runs the accessibility audit UI tests on `macos-15-intel`. That workflow does not sign, notarize, or submit the app.

The existing `.github/workflows/macos-build.yml` for the full edition is unchanged.

## Signing and submission

Signing, notarization, and App Store Connect submission wait until Hunter Thompson's individual Apple Developer enrollment is active. The bundle ID in the project is `office.thompson.MacOSManagerStore`. That App ID has to be registered after the account is approved. This folder does not contain certificates, API keys, or a submit step.
