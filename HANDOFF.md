# Native test handoff

This file is instructions and a record of what has already been run. It is not an installer. No `.pkg` and no `.app` have been built.

## Minimum system

The source requires macOS 14 Sonoma or later. It does not run on Mac OS X 10.10 or on any 10.x release.

The floor comes from the interfaces this source calls:

- `AccessibilityNotification.Announcement` is a macOS 14 interface. The app uses it to speak status changes.
- The two-value `onChange` form used for the sidebar is a macOS 14 interface.
- `NavigationSplitView` needs macOS 13.
- The SwiftUI `App` entry point needs macOS 11.

Lowering the deployment target to 10 would not compile. The Xcode target and `MacOSManagerApp/Info.plist` both stay at 14.0. The 2018 Intel Mac mini (`Macmini8,1`) can run Sonoma 14 and Sequoia 15. Apple's pages in this catalog do not list it for Tahoe 26 or macOS 27. If that mini is still on Ventura 13 or earlier, this app will not launch until that Mac is updated to at least Sonoma by some other Apple method. The package does not perform that update.

The friend's Mac model and macOS version are not known yet. Before expecting a launch, record the model identifier from System Information and the macOS version from About This Mac. If the version is older than 14, stop. Do not treat a failed launch as a VoiceOver result.

## What a Mac build produces

`scripts/package-macos-app.sh` refuses to run on Linux. On a Mac with Xcode it builds a universal `x86_64` and `arm64` app, deployment target 14.0, then an unsigned package that copies `MacOSManager.app` into `/Applications`. The package has no scripts. Installing it does not format a disk, run `createinstallmedia`, or start a macOS install. It is not Developer ID signed and not notarized.

Gatekeeper's reaction to that downloaded package has not been tested. Do not turn off Gatekeeper and do not remove the quarantine flag in order to skip that observation.

## A. Build and unit tests

These do not speak and do not touch a disk.

On Linux, already run: `swift test` reached 29 passing tests, then `testPreferredReleaseStaysOnlyWhenStillOffered` and `testLocalInstallAndUSBAreDifferentCommands` passed later. `scripts/check-intel-pkg-setup.sh` checks the project settings only. It does not build a package.

On the Mac:

```sh
scripts/check-intel-pkg-setup.sh
scripts/package-macos-app.sh
```

Record whether `lipo` shows both `x86_64` and `arm64`, whether `vtool` shows minimum macOS 14.0, and the `codesign` lines. Expect the app and the package to be unsigned.

## B. Keyboard and VoiceOver, no disk writes

Do this only after the app launches. A successful build is not this test. Hearing speech is the result that counts.

1. Turn VoiceOver on with Command-F5, or hold Command and press Touch ID three times.
2. Walk About, Identify this Mac, Compatible versions, Download from Apple, and Install using only the keyboard and VoiceOver.
3. Confirm each control has a name, that focus moves in order, and that a lookup speaks a status line.
4. On Install, confirm two separate choices: "Install on this Mac" and "Create a bootable USB installer".
5. "Install on this Mac" may be pressed only to see that it would open Apple's installer. Stop before Apple's window changes a disk. This choice does not run `createinstallmedia`.
6. Look for disks. Confirm the startup disk is named and is not offered as a USB button.
7. Select a USB and confirm VoiceOver speaks "ALL DATA ON THE SELECTED USB WILL BE ERASED" along with that USB's name and size. Type a wrong name and confirm nothing starts.
8. Press Cancel during a disk listing if one is running, and confirm a cancellation is spoken.

Stop there if the Mac's owner has not approved a disposable target.

## C. USB or macOS install

Do not use the Mac's normal internal disk. Do not use a disk the owner has not named out loud as disposable.

Only after that approval: choose that external volume, type its name exactly, and start "Create bootable USB installer". That runs Apple's `createinstallmedia`, which erases the named volume. "Install on this Mac" continues in Apple's own window and can change the Mac. Neither action has been run.

## Not available from this workspace

No Mac worker is connected. The GitHub workflow is manual-only and has not been run. No repository was created, and no package was uploaded.
