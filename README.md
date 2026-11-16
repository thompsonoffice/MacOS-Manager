# macOS Manager

Private review prototype. It identifies a Mac and shows which macOS versions Apple publishes for that model, then opens Apple's own download pages.

This is not a finished product. The Install screen can open Apple's installer for this Mac, or prepare a bootable USB installer after a typed volume name. Neither action has been run on a disk here. An earlier planning note used the name macOS Companion and described every version from Mac OS X 10.5 onward. That note is not this product. The name here is macOS Manager. The app itself requires macOS 14 or later. Listing an older system for a target Mac does not mean this app runs on Mac OS X 10.

## What this copy does

- Looks up a model identifier, Apple's model name, or a part number.
- Says whether that Mac is Apple silicon or Intel, using Apple's published introduction rules, and whether Apple lists it as a T2 Mac.
- Shows macOS Catalina 10.15 through macOS 27. A version counts only when Apple's compatibility page uses the exact model name.
- For macOS 27, also applies Apple's statement that macOS 27 is compatible with any Mac with Apple silicon. The screen says when that sentence is the reason.
- Opens Apple's Software Update instructions, App Store links, and disk-image links. It does not download the installer.
- On a Mac, can try `sysctl` `hw.model` and `hw.machine`. That call has not been run here, and it has not been tried inside a signed App Sandbox.

If Apple's pages disagree, or a name is only similar, the result says so. It does not guess. The macOS version that shipped from the factory is not in this catalog. The installers Software Update would offer a particular Mac today are also unknown here.

## What this copy does not do

- `softwareupdate`, `diskutil`, and `createinstallmedia` are prepared as argument lists. They have not been run against a real disk or Apple's tools in this workspace.
- App Store Review Guideline 2.4.5(v) says a Mac App Store app may not request root. Apple's USB command needs an administrator password. This prototype does not claim a USB writer is eligible for the store, and it does not choose between an App Store edition and a direct download.
- No Apple installer is bundled. No signing certificate, payment, or App Store submission is included.
- Versions older than Catalina have no per-model list here. Apple still publishes some older download links. Those links are not treated as proof that a Mac can run that version.

## Layout

- `Sources/MacOSManagerCore` is pure Swift. It holds the Apple facts and the lookup rules.
- `Tests/MacOSManagerCoreTests` checks those rules.
- `MacOSManagerApp` is the SwiftUI app. It is not part of the Swift package, so Linux does not try to compile SwiftUI.
- `MacOSManager.xcodeproj` is the unsigned macOS app project.
- `Tools/extract_catalog.py` rebuilt `catalog.json` from Apple Support HTML on 2026-11-06. The HTML is not in this tree.

## Tests on Linux

These tests were run on this machine. SwiftUI was not compiled.

```sh
swift test
```

Result on 2026-11-08, Swift 6.2.3, Ubuntu 24.04, x86_64: 29 tests, 0 failures. Those tests cover the catalog and the install workflow. They do not compile SwiftUI.

The toolchain used here was the official Swift 6.2.3 release for Ubuntu 24.04 from swift.org. It has no macOS SDK.

## Package a direct download

The intended download is an unsigned package that copies the app into `/Applications`. It is not a Mac App Store build, and it is not notarized. No package was produced here.

The recovery Mac is a 2018 Intel Mac mini (`Macmini8,1`). Apple's pages in this catalog list it through macOS Sequoia 15, including Sonoma 14, and not through Tahoe 26 or macOS 27. The app's deployment target is macOS 14, which that mini can run. It will not launch on that mini if the mini is still on Ventura or earlier. The Xcode target builds both `x86_64` and `arm64`, with only-active-arch turned off, so an Apple silicon build machine does not drop the Intel slice.

GitHub's runner list includes `macos-15-intel` as an Intel machine. `macos-latest` and `macos-26` are arm64 and are not the workflow's runner. The manual workflow was not started. GitHub is not logged in here, and no repository was created.

On a Mac with Xcode:

```sh
scripts/package-macos-app.sh
```

The script runs `swift test`, then `xcodebuild` with signing off, checks that `MacOSManager.app` contains a real executable, prints architectures and minimum system version from that binary, records `codesign` status, and writes `build/product/MacOSManager-unsigned-<time>.zip`. It does not notarize.

On 2026-11-08 the same script was run on this Linux x86_64 host. It exited 2 and printed: xcodebuild absent, no .app created. No connected Mac worker was available. That is the unmet requirement: a Mac allowed to run macOS, with Xcode. A Linux test result is not that app.

The project deployment target is macOS 14 because announcements use `AccessibilityNotification.Announcement`. The built app's real minimum version and architectures are whatever `vtool` and `lipo` print when the script runs on a Mac. Do not treat the project setting as a measured binary.

## Not in this app

A later Mac client for taking a system on the go would be a different product. It would have to treat APFS containers, FileVault, recoveryOS, and whether a volume can boot as separate facts. None of that is implemented here.

## VoiceOver

Every control in the app source has a label, and the important ones have a hint. Results are also written on screen and posted as an announcement. That is source intent only. It has not been heard with VoiceOver.

Apple's own on switch, from the VoiceOver User Guide: Command-F5, or hold Command and press Touch ID three times.

## Refreshing the Apple facts

`catalog.json` is the data the app uses. To rebuild it, download the Apple pages named in `REVIEW.md`, save them under the paths `Tools/extract_catalog.py` expects, and run:

```sh
python3 Tools/extract_catalog.py
swift test
```

The checked-in catalog was retrieved 2026-11-06.

## Mac App Store edition

`MacOSManagerStore/` is a separate, sandboxed edition. It helps a VoiceOver user install, upgrade, or downgrade macOS on the Mac itself by opening Apple's official installer or Software Update pages. Apple handles the download and progress. It does not include the full edition's bootable USB installer code, and it does not replace this itch.io edition.

See `MacOSManagerStore/README.md` for layout, tests, review notes, and the Guideline 4.2 risk note. Signing and App Store submission wait until the individual Apple Developer account is active.

