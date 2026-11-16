# App Store Review Guideline 4.2, minimum functionality

This is an honest risk note, not a claim that Apple will approve the app.

## The risk

Guideline 4.2 says apps should include features, content, and UI that elevate them beyond a repackaged website. An app that only opens Apple Support or App Store links can be rejected as a thin wrapper, or as having insufficient functionality.

This edition's purpose is narrow on purpose: help a VoiceOver user see which macOS versions Apple lists for this Mac, then open Apple's official installer or Software Update page so they can install, upgrade, or downgrade on that Mac. Apple handles the download and progress. The sandbox forbids the privileged installer and USB work that lives in the full edition.

Reviewers may still decide that identifying a Mac and opening official Apple pages is not enough unique functionality.

## What this edition does that is not just a website

- It reads the model identifier on device and matches it to a bundled, sourced table (the lookup works offline).
- It applies published compatibility rules, including exact model-name matching and Apple's Apple silicon statement, and it says so when a similar name is not treated as a match.
- It marks the currently installed version and states whether a choice would upgrade, downgrade, or reinstall what is already running.
- The interface is written for VoiceOver: labeled controls, hints, headers, a plain-language status region, and spoken announcements. Status work is asynchronous so the window does not freeze.

These are real features, but they may not be enough for every reviewer.

## What would make a rejection more likely

- Marketing text that promises the app itself installs or downgrades macOS, when it only opens Apple's official pages.
- A submission that looks like a catalog of links, with little on-device behavior.
- Links to an external store, or a prompt to buy the full USB edition (Guideline 3.1.1 / 3.1.3). This app must not include those links. A plain sentence that USB creation is in a separate full edition is already as far as it should go.

## What this note is not

It is not legal advice, and it is not a guarantee of approval. Signing and submission wait for Apple Developer account activation. A first review on a physical Mac with VoiceOver should happen before a paid submission.
