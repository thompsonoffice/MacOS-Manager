# App Store review notes

Use this text in App Store Connect, Notes for Review, when Hunter's individual Apple Developer account is active and this edition is submitted. Do not submit until that account is approved. The seller name is Hunter Thompson.

## Suggested notes for review

macOS Manager (App Store edition) helps VoiceOver users install, upgrade, or downgrade macOS on the Mac they are using.

The app reads the Mac's model identifier (`sysctl hw.model`), shows the friendly model name from a bundled compatibility table, and lists every macOS version Apple's official support pages say is compatible with that model. It marks the version currently installed.

For each compatible version, a button opens Apple's official route only:

- The Mac App Store product page, when Apple publishes one for that version.
- Otherwise Apple's official support article (the How to download macOS page, the macOS 27 upgrade article, or that version's compatibility page).

The app does not download or install macOS itself, does not run the `softwareupdate` command, does not run `createinstallmedia`, and does not include a privileged helper. Apple's own App Store or Support page handles the download and progress.

The compatibility table is bundled with the app. It was read from public Apple Support pages. The app does not collect personal data (Privacy Nutrition Label: Data Not Collected). Opening an Apple page uses Apple's own site or the App Store.

Creating a bootable USB installer is not part of this app. It is a feature of a separate, direct-download edition. This App Store edition does not include that code and does not link to an external store.

No demo account is required. The app works offline except when the user chooses to open an official Apple page.

The signed archive, screenshots, and VoiceOver review on a physical Mac still have to be prepared after the developer account is active. This source tree is not a submission.

## Privacy

Privacy Nutrition Label: Data Not Collected. `App/PrivacyInfo.xcprivacy` sets `NSPrivacyTracking` to false and lists no collected data types.
