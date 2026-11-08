# Review notes

## Two install choices and GitHub, 2026-11-08

The Install screen now names both choices. Install on this Mac only opens Apple's installer (`/usr/bin/open` and the app path). Create a bootable USB installer is `createinstallmedia --volume` after the typed volume name matches. The startup disk is shown with its name and size and is not a USB target. One test, `testLocalInstallAndUSBAreDifferentCommands`, passed. That does not launch the app, run VoiceOver, write a USB, or install macOS.

GitHub is not logged in on this host (`gh auth status` says no login). No repository could be listed, and Actions billing could not be read. That is not proof that Actions is disabled. No workflow was started. `.github/workflows/macos-build.yml` is `workflow_dispatch` only, so it does not run from this Origin draft. A private GitHub repository would draw included macOS minutes and can be charged after that. A public repository would be free for standard runners and would publish the source. Neither destination was created.

## Compile readiness, 2026-11-08 9:18 Central

No macOS app was built. No GitHub repository was created and this Origin draft was not mirrored.

Checked, read-only:

- The only git remote is this private Origin draft. There is no GitHub remote. A later manual-only workflow file does not run from here.
- This cloud run has no linked environment. `build` is null. Self-hosted workers and pools visible here: none.
- `xcodebuild` is absent. `scripts/package-macos-app.sh` was syntax-checked with `bash -n`, then run here. Exit 2. Text: `BLOCKER: this host is Linux x86_64.` No zip was written.

That is the blocking requirement: an already authorized Mac build destination for this project, with Xcode, at no new cost and without a new repo. GitHub-hosted macOS can compile, but using it would mean creating or mirroring a GitHub repo, which was not allowed. No existing Mac runner is attached, so zero incremental cost was not available to verify.

Source fixes in this pass, not a GUI test:

- The package script no longer uses `find -quit`, which BSD `find` on macOS rejects.
- The sidebar list uses an optional selection binding, which is the macOS `List` initializer.
- After a lookup, the chosen version stays only if that Mac is still offered it. Otherwise it moves to the newest offered id. One new test passed: `testPreferredReleaseStaysOnlyWhenStillOffered`.
- The last full Linux run remains 29 tests, 0 failures. This pass did not repeat that suite. Those tests still do not prove VoiceOver, a real window, `softwareupdate`, `diskutil`, or `createinstallmedia`.

## Install workflow and build host, 2026-11-08

`swift test`: 29 tests, 0 failures, Swift 6.2.3, Linux x86_64. Ten of those exercise the install workflow with temporary files and stand-in programs. No physical disk was written.

What the tests actually ran:

- A version is selectable only when the report says Apple lists it, or macOS 27's Apple silicon sentence applies.
- `softwareupdate` is given `--fetch-full-installer` and `--full-installer-version` as separate arguments, and only the catalog build (`27.2` for macOS 27). `27.2;touch /tmp/pwned` is rejected.
- A full installer must be an `Install ….app` whose `createinstallmedia` stays inside `Contents`. A symlink to a tool outside the app is rejected.
- Opening the installer is `/usr/bin/open` plus the app path. The argument list has no `--eraseinstall`, `startosinstall`, or `--volume`.
- The startup disk and, by default, internal disks do not produce a USB command. A typed name must match exactly. A name containing `/` is rejected. If the disk's name changes before run, the stand-in program is not started.
- A hostile volume name `Target; echo pwned` stayed one argument. The recorded sudo argument list was `--`, the tool path, `--volume`, and `/Volumes/Target; echo pwned`. The stand-in sudo did not pass that string through a shell.
- `/bin/sh -c` is refused. A sleep process was signalled to stop. Administrator commands can be refused before any process starts.

The Install screen calls this same code: check an app, run the softwareupdate argument list, run `diskutil list -plist`, open the installer, or run createinstallmedia after the typed name matches. Those buttons were not clicked, because the app was not built.

Build route checked the same day:

- Self-hosted workers visible to this run: none. No pool with an idle Mac.
- `xcodebuild` and `xcrun`: absent.
- This Swift install is the Linux toolchain. It has no macOS SDK.
- `scripts/package-macos-app.sh` exited 2: `BLOCKER: this host is Linux x86_64.` No zip and no `.app` were written. Notarization was not attempted.

QEMU, kept separate from the license: this host has `/dev/kvm` and does not have `qemu-system-x86_64` or `qemu-system-aarch64` installed. QEMU as a project can emulate those machines. That was not demonstrated here, and no macOS image was downloaded. Apple's macOS 27 license, section 2B(iii) at https://www.apple.com/legal/sla/docs/macOS27.pdf, allows virtual copies only on an Apple-branded computer you own or control that is already running the Apple Software. This host is not that computer, so it is not a legitimate macOS test route. Section 2D says the software is supported only on Apple-branded hardware.

Still needs a person at a licensed Mac, and a successful `xcodebuild` would not finish these:

- VoiceOver reading every control, focus order, and the spoken progress lines.
- `sysctl hw.model` on that Mac, including inside a signed sandbox if one is used.
- `softwareupdate` actually downloading an installer Apple offers that Mac.
- `diskutil list` on real disks, without erasing the startup disk.
- `createinstallmedia` against a spare USB, including the administrator prompt and the Y confirmation.
- Opening the Install macOS app and completing Apple's own window. That is an installation test, not a compile test.

## Checkpoint 2026-11-08

Measured again on Ubuntu 24.04, x86_64, Swift 6.2.3. No Mac, no Xcode (`xcodebuild` is not installed), no VoiceOver. Commit under test before this checkpoint: `19428a9`.

Command: `swift test`

Result before the error-text fix: `CatalogTests`, 18 tests, 0 failures, about 0.075 seconds.

One narrow defect was real and is fixed here. `CatalogError` had a plain-language `description`, but the app shows `error.localizedDescription`. Swift's default for that is "The operation could not be completed." A separate check printed that generic sentence. `CatalogError` now conforms to `LocalizedError`, and a unit test locks the spoken sentence.

Apple facts were spot-checked the same day, not rebuilt:

- https://support.apple.com/en-us/109033 is still published October 26, 2026. macOS 27 Golden Gate is still 27.2. Tahoe is still 26.7.2. Sequoia is still 15.8.2. Sonoma is still 14.8.9.
- https://support.apple.com/en-us/127255 is still published November 05, 2026.
- https://support.apple.com/en-us/102662 is still published September 14, 2026.
- https://support.apple.com/en-us/127455 still says macOS 27 is compatible with any Mac with Apple silicon.

The catalog retrieved 2026-11-06 was left as-is. Nothing on those four pages had moved.

After the error-text fix, `swift test` was run again: `CatalogTests`, 19 tests, 0 failures, about 0.124 seconds. The new test checks that a missing catalog is described as "The Apple facts catalog is missing from the app resources." and not as "could not be completed."

### License and this host

QEMU's ability to boot an operating system is not the same question as Apple's license, and neither one was treated as proof that this machine can test the app.

Checked 2026-11-08 from Apple's current English licenses, not from a third-party summary:

- https://www.apple.com/legal/sla/docs/macOS27.pdf — Software License Agreement for macOS, "For use on Apple-branded Systems."
- Section 2, "Permitted License Uses and Restrictions," subsection A: a preinstalled copy is licensed "to install, use and run one (1) copy of the Apple Software on a single Apple-branded computer at any one time."
- Section 2B(iii), under "Mac App Store License": "to install, use and run up to two (2) additional copies or instances of the Apple Software, or any prior macOS or OS X operating system software or subsequent release of the Apple Software, within virtual operating system environments on each Apple-branded computer you own or control that is already running the Apple Software," for software development, testing during software development, macOS Server, or personal non-commercial use.
- The next paragraph says that, except as Section 3 allows, 2B(iii) does not permit those virtual copies for service bureau, time-sharing, terminal sharing, relay service, or similar services. Except as Section 2B permits, the Apple Software may not be used to run iOS, iPadOS, watchOS, or tvOS in virtual environments on Mac computers.
- Section 2D: "the Apple Software is supported on only Apple-branded hardware that meets specified system requirements as indicated by Apple."
- Section 3, "Leasing for Permitted Developer Services," subsection D, "Virtualization": a lessor or a lessee, but not both, may run additional virtual copies "in accordance with Section 2B(iii)," and a lessor may virtualize only a single instance as a provisioning tool. That still points back to 2B(iii). It is a lease term, not a grant for any computer.
- https://www.apple.com/legal/sla/docs/macOSTahoe.pdf uses the same Section 2B(iii) wording for the virtual copies.

This host, measured the same day: Linux 6.12.113+ on x86_64, CPU reported as Intel Xeon, vendor GenuineIntel. `/dev/kvm` exists. `qemu-system-x86_64` and `qemu-system-aarch64` are not installed. `sw_vers` and `xcodebuild` are absent. `/System/Library/CoreServices/SystemVersion.plist` is absent. Nothing identified this machine as an Apple-branded computer already running Apple Software. No macOS image was downloaded and QEMU was not installed. A report that QEMU can virtualize macOS on non-Apple hardware was not tested here and is not a substitute for Section 2B(iii) or for a VoiceOver pass.

### Working, and tested

The Swift core, given an identifier, Apple model name, or part number, returns records from the bundled catalog (159 models). It separates three facts: the name is or is not on Apple's compatibility page, Apple's macOS 27 Apple-silicon sentence when the exact name is absent, and the statement that today's Software Update offer is unknown. Download guidance returns Apple's published URL and sets `runsSoftwareUpdateCommand` and `bundlesInstaller` to false. USB status is an explicit non-implementation: it does not erase, does not request root, and does not run `createinstallmedia`. Part-number stems in the catalog do not collide (696 published part numbers, 692 stems, 0 prefix collisions).

### Source only, not a running feature

The SwiftUI app is source. It has labels, hints, a status line, and announcement calls. None of that has been compiled or heard. "Read the model identifier" calls `sysctlbyname("hw.model")` and `sysctlbyname("hw.machine")` in app source. That function has never been executed. Tests that mention `arm64` or `x86_64` inject a fixture. They do not read this machine. Opening an Apple URL is `NSWorkspace.shared.open` in app source. No URL was opened from the app. The App Sandbox entitlement is in the project file. This copy is unsigned, so the sandbox is not enforced, and sandbox behavior of `sysctl` is unmeasured.

### Not started

No installer bytes are downloaded. No disk is listed. No erase confirmation exists because there is no erase action. No signing identity, notarization, store listing, or payment exists.

### Smallest useful next milestone

One session on a real Mac: compile this project, run it under VoiceOver, type or read one model identifier, hear the compatibility result, and open one Apple page. Stop there. Do not add the USB writer in that session. USB creation needs a signed or directly distributed Mac build, an administrator prompt, a chosen volume, and a typed erase confirmation. Those cannot be rehearsed here, and App Store Guideline 2.4.5(v) still forbids root in a store app.

Fastest defensible next task: that Mac session, done by someone with a Mac. More Linux-only work will not make this releasable. Hunter does not currently have a Mac.

### Still blocked without hardware

- Whether the Xcode project builds.
- Whether VoiceOver reads every control and the status announcement.
- Whether `sysctl hw.model` works, including inside a signed sandbox.
- Whether the Software Update help-action link opens from this app.
- Any USB or erase behavior. Do not test that on a disk yet. It is not implemented.

## Review notes, 2026-11-06

macOS Manager, private prototype. No App Store submission, no signing, no USB writer, no pull request.

## Tests actually run

Command: `swift test`

Host: Ubuntu 24.04, x86_64, Swift 6.2.3 (swift-6.2.3-RELEASE).

Result: `CatalogTests`, 18 tests, 0 failures.

The tests check the bundled catalog, not a live Mac:

- macOS 27 lists MacBook Pro (14-inch, M6), identifier Mac18,1. macOS Tahoe 26 does not list that name.
- MacBook Pro (16-inch, 2019), identifier MacBookPro16,1, is Intel, is on Apple's T2 list, is listed for Tahoe, and is not listed for macOS 27.
- Mac mini (M6), identifier Mac18,5, is not the exact string on the macOS 27 page. The page says "Mac mini (M6 or M5 Pro)". The result does not treat that as the same name. It does apply Apple's sentence that macOS 27 is compatible with any Mac with Apple silicon.
- An `x86_64` reading for that mini is reported as a contradiction, and the Apple silicon sentence is not applied.
- Mac14,8 is both Mac Pro (2023) and Mac Pro (Rack, 2023). macOS 27 lists only "Mac Pro (2023)". The result keeps both records.
- MacBookPro15,1 is both the 2018 and 2019 15-inch MacBook Pro. Both are kept.
- Sonoma's "iMac (24-inch, 2023)" is not treated as "iMac (24-inch, 2023, Four ports)".
- "MacBook Pro (14-inch, Nov 2023)" is not treated as "MacBook Pro (14-inch, 2023)".
- Unknown identifiers claim nothing.
- Part number MHWT4LL/A maps to Mac18,1.
- MacBook Air (M1, 2020) is Apple silicon. MacBook Air (Retina, 13-inch, 2020) is Intel and on the T2 list.
- MacBook Neo (13-inch, A18 Pro) has no hw.model in this catalog. The marketing name is listed for macOS 27 and Tahoe.
- Sequoia has Apple's App Store id 6596773750. macOS 27 has no App Store link in Apple's download article. The core flags say it does not run `softwareupdate` and does not bundle an installer.
- The USB status flags are all false: not implemented, does not erase, does not request root, does not run `createinstallmedia`.
- Mac Pro (Mid 2012) keeps Apple's Mojave footnote about a Metal-capable graphics card.
- Every name on the eight compatibility pages either matches a model exactly or is one of the similar-name cases above.

## Not tested

- SwiftUI was not compiled. There is no Mac and no Xcode in this workspace.
- VoiceOver was not turned on. Keyboard focus was not tried in a running app.
- `sysctl hw.model` was not called. Whether the App Sandbox allows it is unknown.
- The Software Update settings link from Apple's user guide was not opened from this app.
- No installer was downloaded. No disk was touched.

## Limits of the facts

Retrieved 2026-11-06 from the public pages below.

- Hardware support and "Apple is offering this download today" are different. Software Update, and `softwareupdate --list-full-installers`, are per Mac. This app does not run that command, so the current offer is unknown.
- Factory macOS is not stated on the identify pages that were parsed. It is unknown.
- Processor class comes from Apple's model-introduction article, not from reading the chip. A live `hw.machine` value is compared when a reading is supplied. `arm64` agrees with Apple silicon. `x86_64` agrees with Intel. A clash is shown and the macOS 27 blanket sentence is withheld.
- Similar names are shown and are not counted as support.
- One identifier can belong to more than one Apple model. Both stay on screen.
- MacBook Neo's tech specs page does not publish an hw.model identifier. Lookup by the marketing name works. Lookup by identifier cannot find it until Apple publishes one.
- There is no per-model list here for 10.14 or earlier. Some of those versions still have a download link on Apple's article. That link is not a compatibility claim.
- macOS 16 through 25 do not appear because Apple's latest-version table does not list them.

## Next check on a real Mac

1. Run `swift test`, then the `xcodebuild` command in the README. Record whether the app compiles. This workspace cannot say that it does.
2. Turn VoiceOver on. Walk About, Identify, Compatible versions, Download, and USB with the keyboard only. Confirm every control has a name, that focus moves in order, and that the status announcement is spoken when a lookup finishes.
3. On an Apple silicon Mac and an Intel Mac, use "Read the model identifier from this Mac". Compare it with System Information. Repeat the same build after it is signed with the App Sandbox entitlement turned on, and record whether `sysctl` still returns `hw.model`.
4. Open Software Update from the button. Confirm it lands in System Settings, or record that the help-action link does nothing outside Apple's user guide.
5. Open one App Store link and the macOS 27 article. Confirm no installer is fetched by this app.
6. Do not point the USB screen at a real disk. There is no writer in this build. A later direct-distribution tool, if Hunter asks for one, still needs a typed erase confirmation and Apple's administrator prompt. It is not started here.

## Apple pages used

Compatibility and version names:

- https://support.apple.com/en-us/102662 published September 14, 2026. Download methods, App Store links, disk images.
- https://support.apple.com/en-us/109033 published October 26, 2026. Latest build table. macOS 27 Golden Gate is 27.2. Tahoe is 26.7.2. Sequoia is 15.8.2.
- https://support.apple.com/en-us/127255 published November 05, 2026. macOS 27 model list.
- https://support.apple.com/en-us/127455 published September 14, 2026. "macOS 27 is compatible with any Mac with Apple silicon, which includes any Mac with an M-series chip or A-series chip." Software Update offers only updates compatible with that Mac.
- https://support.apple.com/en-us/122867 published September 14, 2026. Tahoe.
- https://support.apple.com/en-us/120282 published September 15, 2025. Sequoia.
- https://support.apple.com/en-us/105113 published September 16, 2024. Sonoma.
- https://support.apple.com/en-us/102861 published September 17, 2025. Ventura.
- https://support.apple.com/en-us/103260 published June 05, 2025. Monterey.
- https://support.apple.com/en-us/103111 published June 05, 2025. Big Sur.
- https://support.apple.com/en-us/102765 published June 05, 2025. Catalina.

Model identifiers:

- https://support.apple.com/en-us/108052 MacBook Pro
- https://support.apple.com/en-us/102869 MacBook Air
- https://support.apple.com/en-us/108054 iMac and iMac Pro
- https://support.apple.com/en-us/102852 Mac mini
- https://support.apple.com/en-us/102231 Mac Studio
- https://support.apple.com/en-us/102887 Mac Pro
- https://support.apple.com/en-us/103257 MacBook
- https://support.apple.com/en-us/126322 MacBook Neo tech specs. Chip and year only. No model identifier on that page.
- https://support.apple.com/en-us/102767 published November 04, 2026. How to find the model identifier. Command-4 speaks the serial number.

Processor and startup:

- https://support.apple.com/en-us/116943 published May 12, 2026. Which Macs have Apple silicon.
- https://support.apple.com/en-us/103265 published May 27, 2026. T2 Macs.
- https://support.apple.com/en-us/101578 published September 14, 2026. Bootable installer. `sudo` and createinstallmedia. Power button on Apple silicon. Option key on Intel. T2 external-boot note.
- https://support.apple.com/guide/mac-help/software-update-settings-on-mac-mchla7037245/mac Software Update settings, including the help-action link `x-help-action://openPrefPane?bundleId=com.apple.Software-Update-Settings.extension`
- https://support.apple.com/guide/voiceover/turn-voiceover-on-or-off-vo2682/mac Command-F5, and Command plus Touch ID three times.

Rules:

- https://developer.apple.com/app-store/review/guidelines/ updated October 16, 2026. Guideline 2.4.5(v): Mac App Store apps may not request escalation to root privileges or use setuid attributes. 2.4.5(i) requires the App Sandbox. 2.5.2 says apps may not read or write outside the container.

App Store links copied from the September 14, 2026 download article:

- Sequoia 15: `macappstores://apps.apple.com/app/macos-sequoia/id6596773750?mt=12`
- Sonoma 14: `macappstores://apps.apple.com/app/macos-sonoma/id6450717509?mt=12`
- Ventura 13: `macappstores://apps.apple.com/app/macos-ventura/id1638787999?mt=12`
- Monterey 12: `macappstores://apps.apple.com/app/macos-monterey/id1576738294?mt=12`
- Big Sur 11: `macappstores://apps.apple.com/app/macos-big-sur/id1526878132?mt=12`
- Catalina 10.15: `macappstores://apps.apple.com/app/macos-catalina/id1466841314?mt=12`
- Mojave 10.14: `macappstores://apps.apple.com/app/macos-mojave/id1398502828?mt=12`
- High Sierra 10.13: `macappstores://apps.apple.com/app/macos-high-sierra/id1246284741?mt=12`

Disk images on that same article, with no per-model list in this catalog: Sierra 10.12, El Capitan 10.11, Yosemite 10.10, Mountain Lion 10.8, Lion 10.7. Mavericks 10.9 is on the latest-version table and has no link on the download article. macOS 27 and Tahoe have no App Store or disk-image link there.
