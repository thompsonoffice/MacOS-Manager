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
