# App Store review notes

Use this text in App Store Connect, Notes for Review, when Hunter's individual Apple Developer account is active and this edition is submitted. Do not submit until that account is approved. The seller name is Hunter Thompson.

## Suggested notes for review

macOS Manager (App Store edition) helps VoiceOver users install, upgrade, or downgrade macOS on the Mac they are using.

The app reads the Mac's model identifier (`sysctl hw.model`), shows the friendly model name from a bundled compatibility table, and lists every macOS version Apple's official support pages say is compatible with that model. It marks the version currently installed.

For a chosen version, "Can my Mac run this?" checks this Mac and speaks one result, "Ready." or "Not ready, here's why." The checks are:

- Whether Apple's table lists this model for that version.
- Free space on the startup volume, read with a volume resource value, compared with Apple's stated requirement when Apple publishes one (Catalina and Big Sur, as cited in SOURCES.md). For later versions, Apple's current pages do not state a number, and the app says that instead of guessing.
- Memory, when Apple states a minimum. Otherwise the app says Apple did not state one.
- Whether the choice is an upgrade, the same version, or a downgrade. For a downgrade, the app explains that Apple's installer can't install an older macOS over a newer one on the local drive, and that this needs a bootable USB installer or an Apple restore. It says the full edition is a separate product. It does not link to that product and does not show a price.
- Battery and power, from IOKit power sources (`IOPSCopyPowerSourcesInfo`). The app warns if the Mac is on battery or below 50 percent and suggests plugging in. A desktop with no battery is not warned. The 50 percent line is this app's warning, and the screen says so.

"Before you install" is a checklist: back up with Time Machine, stay plugged in, use a stable internet connection, expect restarts, and a VoiceOver note that speech may be unavailable for a short time at a restart (Command-F5 turns VoiceOver on or off). The Time Machine button opens System Settings with `x-apple.systempreferences:com.apple.Time-Machine-Settings.extension`. A second button opens Apple's https Time Machine guide. The checklist does not run a backup and does not install macOS.

Free space, memory, and power stay on the Mac. They are not collected.

For each compatible version, a button opens Apple's official route only:

- The Mac App Store product page, when Apple publishes one for that version.
- Otherwise Apple's official support article (the How to download macOS page, the macOS 27 upgrade article, or that version's compatibility page).

The app does not download or install macOS itself, does not run the `softwareupdate` command, does not run `createinstallmedia`, and does not include a privileged helper. Apple's own App Store or Support page handles the download and progress.

The compatibility table is bundled with the app. It was read from public Apple Support pages. The app does not collect personal data (Privacy Nutrition Label: Data Not Collected). Opening an Apple page uses Apple's own site or the App Store.

Creating a bootable USB installer is not part of this app. It is a feature of a separate, direct-download edition. This App Store edition does not include that code and does not link to an external store.

No demo account is required. The app works offline except when the user chooses to open an official Apple page or Time Machine in System Settings.

To try the readiness check: open the app, choose "Can my Mac run ..." under a version, and listen for Ready or Not ready. Then choose "Show the checklist before you install." Please do not expect the app to download or install macOS. The accessibility audit in CI does not click those Apple buttons.

The signed archive, screenshots, and VoiceOver review on a physical Mac still have to be prepared after the developer account is active. This source tree is not a submission.

## Privacy

Privacy Nutrition Label: Data Not Collected. `App/PrivacyInfo.xcprivacy` sets `NSPrivacyTracking` to false and lists no collected data types.
