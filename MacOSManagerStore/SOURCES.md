# Sources for the App Store edition compatibility table

The bundled table in `Sources/MacOSManagerStoreCore/Resources/catalog.json` was read from public Apple Support and App Store pages on **2026-11-06**. The same facts were extracted for the full edition by `Tools/extract_catalog.py` in the repository root. This App Store edition copies that table and **omits Apple CDN disk-image installer URLs**. Those older versions open Apple's official [How to download macOS](https://support.apple.com/en-us/102662) article instead.

A model is listed for a macOS version only when its exact Apple model name appears on that version's compatibility page, or when Apple's published Apple silicon statement covers it. This edition does not invent compatibility for versions older than macOS Catalina, because those pages are not in the table.

## Apple pages used

The catalog's `retrieved` field is `2026-11-06`. Article published dates, where Apple printed them, are stored next to each URL in `catalog.json` (`rules` and each release record).

- https://support.apple.com/en-us/116943
- https://support.apple.com/en-us/103265
- https://support.apple.com/en-us/102662
- https://support.apple.com/guide/mac-help/software-update-settings-on-mac-mchla7037245/mac
- https://support.apple.com/en-us/127455
- https://support.apple.com/guide/voiceover/turn-voiceover-on-or-off-vo2682/mac
- https://developer.apple.com/app-store/review/guidelines/
- https://support.apple.com/en-us/101578
- https://support.apple.com/en-us/127255
- https://support.apple.com/en-us/122867
- https://support.apple.com/en-us/120282
- https://apps.apple.com/app/macos-sequoia/id6596773750
- https://support.apple.com/en-us/105113
- https://apps.apple.com/app/macos-sonoma/id6450717509
- https://support.apple.com/en-us/102861
- https://apps.apple.com/app/macos-ventura/id1638787999
- https://support.apple.com/en-us/103260
- https://apps.apple.com/app/macos-monterey/id1576738294
- https://support.apple.com/en-us/103111
- https://apps.apple.com/app/macos-big-sur/id1526878132
- https://support.apple.com/en-us/102765
- https://apps.apple.com/app/macos-catalina/id1466841314
- https://apps.apple.com/app/macos-mojave/id1398502828
- https://apps.apple.com/app/macos-high-sierra/id1246284741
- https://support.apple.com/en-us/108052
- https://support.apple.com/en-us/102869
- https://support.apple.com/en-us/108054
- https://support.apple.com/en-us/102852
- https://support.apple.com/en-us/102231
- https://support.apple.com/en-us/102887
- https://support.apple.com/en-us/103257
- https://support.apple.com/en-us/126322

Each model record also stores the identify-page `sourceURL` it was read from. The list above is the unique set of those URLs plus the shared rules, compatibility, download, and App Store product pages.

## What this edition does not take from those pages

- It does not bundle or fetch Apple installer files.
- It does not run `softwareupdate` or `createinstallmedia`.
- It does not include the full edition's USB or privileged command code.

## Free space and memory, checked 2026-11-16

The readiness check compares free space on the startup volume with a number only when Apple states one. The startup volume is read with URL resource values (`volumeAvailableCapacityForImportantUsage`, then `volumeAvailableCapacity`). That is not raw disk access. Memory is `ProcessInfo.physicalMemory`. Nothing is sent off the Mac.

Apple's gigabytes for storage are treated as decimal gigabytes (1 GB = 1,000,000,000 bytes), the same scale Finder uses. Apple's "4GB of memory" is treated as 4 gibibytes, which is the size a Mac reports for 4 GB of installed memory.

### Figures Apple states

- macOS Catalina 10.15. [macOS Catalina - Technical Specifications](https://support.apple.com/en-us/118458) states 4GB of memory, 12.5GB of available storage when upgrading from OS X El Capitan 10.11.5 or later, and up to 18.5GB when upgrading from an earlier release. If this app cannot read the installed version, it uses the higher figure and says so.
- macOS Big Sur 11. [macOS Big Sur - Technical Specifications](https://support.apple.com/en-us/111980) states 4GB of memory, 35.5GB of available storage when upgrading from macOS Sierra or later, and up to 44.5GB when upgrading from an earlier release. If the installed version was not read, this app uses the higher figure and says so.

### Versions with no official free-space or memory number

These current Apple pages were read on 2026-11-16. They name compatible Macs, or explain how to upgrade, and they do not state a gigabyte figure for free space or memory. This edition does not invent one. The check says Apple did not state a number.

- macOS Monterey 12: https://support.apple.com/en-us/103260
- macOS Ventura 13: https://support.apple.com/en-us/102861
- macOS Sonoma 14: https://support.apple.com/en-us/105113
- macOS Sequoia 15: https://support.apple.com/en-us/120282
- macOS Tahoe 26: https://support.apple.com/en-us/122867
- macOS 27 Golden Gate: https://support.apple.com/en-us/127255 and the upgrade article https://support.apple.com/en-us/127455

Also checked, and not used as a startup-volume requirement:

- https://support.apple.com/en-us/102662 does not state a startup-volume size.
- https://support.apple.com/en-us/102531 says to free up storage if the installer reports that there is not enough. It does not state a gigabyte figure.
- https://support.apple.com/en-us/101578 says a 32GB flash drive has more than enough space for any macOS installer, and 16GB is enough for most earlier installers. That is the USB stick, not free space on the startup volume, so the readiness check does not use it.

No current Apple technical-specifications page with a storage or memory number was found for Monterey, Ventura, Sonoma, Sequoia, Tahoe, or macOS 27.

## Power, checklist, and VoiceOver

Power uses `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, and `IOPSGetPowerSourceDescription`. Those IOKit calls are public and do not need a privileged helper. A Mac with no internal battery, such as a desktop, gets no battery warning. This app warns when the Mac is on battery or the internal battery is below 50 percent. Apple's pages above do not state that 50 percent figure. The sentence in the app says the percentage is this app's warning.

The checklist opens Time Machine with Apple's System Settings URL `x-apple.systempreferences:com.apple.Time-Machine-Settings.extension`. If that does not open, the next button is the https guide [Back up your Mac with Time Machine](https://support.apple.com/guide/mac-help/back-up-your-mac-with-time-machine-mh35860/mac). Neither address is a purchase link.

Other checklist facts, in plain language:

- Back up before upgrading: https://support.apple.com/en-us/127455 and https://support.apple.com/en-us/108382
- The installer needs a stable internet connection for the download and for firmware: https://support.apple.com/en-us/102531 and https://support.apple.com/en-us/101578
- The Mac might restart and show a progress bar or a blank screen more than once: https://support.apple.com/en-us/108382
- Turn VoiceOver on or off with Command-F5, or hold Command and press Touch ID three times: https://support.apple.com/guide/voiceover/turn-voiceover-on-or-off-vo2682/mac

A downgrade is described as Apple's installer being unable to install an older macOS over a newer one on the local drive. The app says that needs a bootable USB installer or an Apple restore, and that USB creation is in the separate full edition. There is no link and no price.
