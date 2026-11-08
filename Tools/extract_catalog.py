#!/usr/bin/env python3
"""Extract a factual catalog from Apple Support HTML saved locally.

The HTML files are not committed. They are the public pages listed in
CATALOG_PAGES, downloaded on 2026-11-06. This script writes catalog.json.
It does not guess a match between similar model names.
"""

from __future__ import annotations

import json
import re
from html import unescape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HTML = Path("/tmp/apple")
OUT = ROOT / "Sources" / "MacOSManagerCore" / "Resources" / "catalog.json"

IDENTIFY_PAGES = {
    "108052": "https://support.apple.com/en-us/108052",
    "102869": "https://support.apple.com/en-us/102869",
    "108054": "https://support.apple.com/en-us/108054",
    "102852": "https://support.apple.com/en-us/102852",
    "102231": "https://support.apple.com/en-us/102231",
    "102887": "https://support.apple.com/en-us/102887",
    "103257": "https://support.apple.com/en-us/103257",
}

COMPAT_PAGES = [
    {
        "id": "27",
        "marketingName": "macOS 27 Golden Gate",
        "latestBuild": "27.2",
        "page": "127255",
        "url": "https://support.apple.com/en-us/127255",
        "published": "November 05, 2026",
        "appleSiliconBlanket": {
            "statement": "macOS 27 is compatible with any Mac with Apple silicon, which includes any Mac with an M-series chip or A-series chip.",
            "url": "https://support.apple.com/en-us/127455",
            "published": "September 14, 2026",
            "alsoStatedOn": "https://support.apple.com/en-us/127255",
        },
    },
    {
        "id": "26",
        "marketingName": "macOS Tahoe 26",
        "latestBuild": "26.7.2",
        "page": "122867",
        "url": "https://support.apple.com/en-us/122867",
        "published": "September 14, 2026",
    },
    {
        "id": "15",
        "marketingName": "macOS Sequoia 15",
        "latestBuild": "15.8.2",
        "page": "120282",
        "url": "https://support.apple.com/en-us/120282",
        "published": "September 15, 2025",
    },
    {
        "id": "14",
        "marketingName": "macOS Sonoma 14",
        "latestBuild": "14.8.9",
        "page": "105113",
        "url": "https://support.apple.com/en-us/105113",
        "published": "September 16, 2024",
    },
    {
        "id": "13",
        "marketingName": "macOS Ventura 13",
        "latestBuild": "13.7.8",
        "page": "102861",
        "url": "https://support.apple.com/en-us/102861",
        "published": "September 17, 2025",
    },
    {
        "id": "12",
        "marketingName": "macOS Monterey 12",
        "latestBuild": "12.7.6",
        "page": "103260",
        "url": "https://support.apple.com/en-us/103260",
        "published": "June 05, 2025",
    },
    {
        "id": "11",
        "marketingName": "macOS Big Sur 11",
        "latestBuild": "11.7.11",
        "page": "103111",
        "url": "https://support.apple.com/en-us/103111",
        "published": "June 05, 2025",
    },
    {
        "id": "10.15",
        "marketingName": "macOS Catalina 10.15",
        "latestBuild": "10.15.8",
        "page": "102765",
        "url": "https://support.apple.com/en-us/102765",
        "published": "June 05, 2025",
    },
]

# Public download paths copied from https://support.apple.com/en-us/102662
# (published September 14, 2026). Versions absent from that article's link
# lists have kind "noneOnDownloadArticle". Latest build numbers are from
# https://support.apple.com/en-us/109033 (published October 26, 2026).
DOWNLOADS = {
    "27": {"kind": "noneOnDownloadArticle"},
    "26": {"kind": "noneOnDownloadArticle"},
    "15": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-sequoia/id6596773750?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-sequoia/id6596773750",
    },
    "14": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-sonoma/id6450717509?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-sonoma/id6450717509",
    },
    "13": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-ventura/id1638787999?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-ventura/id1638787999",
    },
    "12": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-monterey/id1576738294?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-monterey/id1576738294",
    },
    "11": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-big-sur/id1526878132?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-big-sur/id1526878132",
    },
    "10.15": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-catalina/id1466841314?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-catalina/id1466841314",
    },
    "10.14": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-mojave/id1398502828?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-mojave/id1398502828",
        "marketingName": "macOS Mojave 10.14",
        "latestBuild": "10.14.6",
    },
    "10.13": {
        "kind": "appStore",
        "macAppStoreURL": "macappstores://apps.apple.com/app/macos-high-sierra/id1246284741?mt=12",
        "httpsURL": "https://apps.apple.com/app/macos-high-sierra/id1246284741",
        "marketingName": "macOS High Sierra 10.13",
        "latestBuild": "10.13.6",
    },
    "10.12": {
        "kind": "diskImage",
        "diskImageURL": "http://updates-http.cdn-apple.com/2019/cert/061-39476-20191023-48f365f4-0015-4c41-9f44-39d3d2aca067/InstallOS.dmg",
        "marketingName": "macOS Sierra 10.12",
        "latestBuild": "10.12.6",
    },
    "10.11": {
        "kind": "diskImage",
        "diskImageURL": "http://updates-http.cdn-apple.com/2019/cert/061-41424-20191024-218af9ec-cf50-4516-9011-228c78eda3d2/InstallMacOSX.dmg",
        "marketingName": "OS X El Capitan 10.11",
        "latestBuild": "10.11.6",
    },
    "10.10": {
        "kind": "diskImage",
        "diskImageURL": "http://updates-http.cdn-apple.com/2019/cert/061-41343-20191023-02465f92-3ab5-4c92-bfe2-b725447a070d/InstallMacOSX.dmg",
        "marketingName": "OS X Yosemite 10.10",
        "latestBuild": "10.10.5",
    },
    "10.9": {
        "kind": "noneOnDownloadArticle",
        "marketingName": "OS X Mavericks 10.9",
        "latestBuild": "10.9.5",
    },
    "10.8": {
        "kind": "diskImage",
        "diskImageURL": "https://updates.cdn-apple.com/2021/macos/031-0627-20210614-90D11F33-1A65-42DD-BBEA-E1D9F43A6B3F/InstallMacOSX.dmg",
        "marketingName": "OS X Mountain Lion 10.8",
        "latestBuild": "10.8.5",
    },
    "10.7": {
        "kind": "diskImage",
        "diskImageURL": "https://updates.cdn-apple.com/2021/macos/041-7683-20210614-E610947E-C7CE-46EB-8860-D26D71F0D3EA/InstallMacOSX.dmg",
        "marketingName": "OS X Lion 10.7",
        "latestBuild": "10.7.5",
    },
}

FAMILIES = [
    "MacBook Pro",
    "MacBook Air",
    "MacBook Neo",
    "MacBook",
    "iMac Pro",
    "iMac",
    "Mac mini",
    "Mac Studio",
    "Mac Pro Server",
    "Mac Pro",
]

CHIP_RE = re.compile(
    r"(A18 Pro|M\d(?:\s+(?:Pro|Max|Ultra))?(?:\s+or\s+M\d(?:\s+(?:Pro|Max|Ultra))?)?)"
)


def strip_tags(value: str) -> str:
    value = re.sub(r"<br\s*/?>", " ", value, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = unescape(value).replace("\xa0", " ").replace("\u200b", "")
    value = re.sub(r"\s+", " ", value).strip()
    return value


def blocks(html: str) -> list[tuple[str, str]]:
    found = []
    for match in re.finditer(r"<(h2|h3|p)\b[^>]*>([\s\S]*?)</\1>", html, flags=re.I):
        text = strip_tags(match.group(2))
        if text:
            found.append((match.group(1).lower(), text))
    return found


def is_model_title(text: str) -> bool:
    if ":" in text or len(text) > 90 or len(text) < 6:
        return False
    if text.startswith(("Identify", "Find ", "Related", "Apple", "Support", "Quick ", "User ", "Tech ")):
        return False
    return text.startswith(("Mac", "iMac"))


def family_of(name: str) -> str:
    for family in FAMILIES:
        if name == family or name.startswith(family + " ") or name.startswith(family + "("):
            return family
    raise SystemExit(f"No family for {name!r}")


def year_in_text(text: str) -> int | None:
    years = [int(item) for item in re.findall(r"\b(?:19|20)\d{2}\b", text)]
    return years[-1] if years else None


def chip_label(name: str, description: str) -> str | None:
    for source in (name, description):
        match = CHIP_RE.search(source)
        if match:
            return match.group(1)
    return None


def split_identifiers(raw: str) -> list[str]:
    # The comma inside MacBookPro16,1 is part of the identifier.
    # A new identifier starts after a comma or semicolon plus whitespace.
    parts = re.split(r"[,;]\s+(?=[A-Za-z])", raw.strip())
    return [part for part in parts if part]


def field_value(text: str, label: str) -> str | None:
    match = re.match(rf"{label}\s*:?\s*(.*)$", text, flags=re.I)
    if not match:
        return None
    value = match.group(1).strip(" *")
    return value or None


def parse_identify(html: str, source_url: str) -> list[dict]:
    footnotes = []
    pending_name = None
    prelude = {"description": "", "yearIntroduced": None, "yearSource": None}
    current = None
    models = []

    def finish():
        nonlocal current
        if current and current.get("identifiers"):
            models.append(current)
        current = None

    for _tag, text in blocks(html):
        if text.startswith("*"):
            footnotes.append(text.lstrip("* ").strip())
            continue
        if is_model_title(text):
            finish()
            pending_name = text
            prelude = {"description": "", "yearIntroduced": None, "yearSource": None}
            current = None
            continue
        if current is None and pending_name:
            year = field_value(text, "Year introduced")
            if year and year.isdigit():
                prelude["yearIntroduced"] = int(year)
                prelude["yearSource"] = "yearIntroducedField"
                continue
            if text.startswith(("This model", "Ports:", "Chip:")):
                prelude["description"] = (prelude["description"] + " " + text).strip()
                continue
        ident = field_value(text, "Model Identifier")
        if ident and pending_name and current is None:
            current = {
                "name": pending_name,
                "family": family_of(pending_name),
                "identifiers": split_identifiers(ident),
                "description": prelude["description"],
                "yearIntroduced": prelude["yearIntroduced"],
                "yearSource": prelude["yearSource"],
                "partNumbers": [],
                "newestOperatingSystemText": None,
                "newestOperatingSystemFootnote": None,
                "sourceURL": source_url,
                "sourceKind": "identifyPage",
                "note": None,
            }
            continue
        if current is None:
            continue
        year = field_value(text, "Year introduced")
        if year and year.isdigit():
            current["yearIntroduced"] = int(year)
            current["yearSource"] = "yearIntroducedField"
            continue
        newest = field_value(text, "Newest compatible operating system")
        if newest:
            starred = text.rstrip().endswith("*") or newest.endswith("*")
            current["newestOperatingSystemText"] = newest.rstrip("*").strip()
            current["_starred"] = starred
            continue
        parts = field_value(text, "Part Numbers") or field_value(text, "Part Number")
        if parts:
            current["partNumbers"] = [part.strip() for part in parts.split(",") if part.strip()]
            continue
        if text.startswith(("This model", "Ports:", "Chip:")):
            current["description"] = (current["description"] + " " + text).strip()

    finish()
    for model in models:
        starred = model.pop("_starred", False)
        if starred and footnotes:
            model["newestOperatingSystemFootnote"] = " ".join(footnotes)
        name_year = year_in_text(model["name"])
        if model["yearIntroduced"] is None and name_year is not None:
            model["yearIntroduced"] = name_year
            model["yearSource"] = "modelName"
        elif (
            model["yearIntroduced"] is not None
            and name_year is not None
            and model["yearIntroduced"] != name_year
        ):
            model["yearIntroduced"] = None
            model["yearSource"] = "conflict"
            model["note"] = (
                "Apple's year introduced field and the year in the model name differ, "
                "so this catalog leaves the year unknown."
            )
        model["chipLabel"] = chip_label(model["name"], model["description"])
        model["description"] = model["description"] or None
    return models


def compatibility_names(html: str) -> list[str]:
    names = []
    seen = set()
    for tag, text in blocks(html):
        if tag != "p":
            continue
        if not is_model_title(text):
            continue
        # Skip the identify-article links, which are not model rows.
        if text.startswith("Identify "):
            continue
        if text not in seen:
            seen.add(text)
            names.append(text)
    return names


def download_record(release_id: str, meta: dict | None = None) -> dict:
    raw = DOWNLOADS[release_id]
    record = {
        "kind": raw["kind"],
        "articleURL": "https://support.apple.com/en-us/102662",
        "articlePublished": "September 14, 2026",
        "macAppStoreURL": raw.get("macAppStoreURL"),
        "httpsURL": raw.get("httpsURL"),
        "diskImageURL": raw.get("diskImageURL"),
    }
    if raw["kind"] == "noneOnDownloadArticle":
        record["note"] = (
            "Apple's download article does not publish an App Store link or a disk image for this version. "
            "Software Update on the Mac shows only updates compatible with that Mac."
        )
    elif raw["kind"] == "appStore":
        record["note"] = (
            "App Store link published on Apple's download article. "
            "The https address is the same product id with the https scheme. "
            "Opening it does not mean this Mac is currently offered the installer."
        )
    else:
        record["note"] = (
            "Disk image URL published on Apple's download article. "
            "This catalog has no per-model compatibility page for this version."
        )
    return record


def main() -> None:
    html_root = DEFAULT_HTML
    models = []
    for page_id, url in IDENTIFY_PAGES.items():
        html = (html_root / f"id-{page_id}.html").read_text(encoding="utf-8", errors="replace")
        models.extend(parse_identify(html, url))

    # MacBook Neo has a marketing name and tech specs, and no hw.model on the
    # tech specs page fetched the same day.
    models.append(
        {
            "name": "MacBook Neo (13-inch, A18 Pro)",
            "family": "MacBook Neo",
            "identifiers": [],
            "description": "Apple A18 Pro chip. Year introduced: 2026.",
            "yearIntroduced": 2026,
            "yearSource": "techSpecsYearIntroduced",
            "partNumbers": [],
            "newestOperatingSystemText": None,
            "newestOperatingSystemFootnote": None,
            "sourceURL": "https://support.apple.com/en-us/126322",
            "sourceKind": "techSpecsWithoutModelIdentifier",
            "note": (
                "Apple's MacBook Neo tech specs page states the A18 Pro chip and year introduced 2026. "
                "That page does not publish an hw.model identifier. "
                "The marketing name is the compatibility-list name."
            ),
            "chipLabel": "A18 Pro",
        }
    )

    releases = []
    for spec in COMPAT_PAGES:
        html = (html_root / f"{spec['page']}.html").read_text(encoding="utf-8", errors="replace")
        names = compatibility_names(html)
        if len(names) < 5:
            raise SystemExit(f"Too few names parsed for {spec['id']}: {len(names)}")
        releases.append(
            {
                "id": spec["id"],
                "marketingName": spec["marketingName"],
                "latestBuild": spec["latestBuild"],
                "latestBuildSourceURL": "https://support.apple.com/en-us/109033",
                "latestBuildSourcePublished": "October 26, 2026",
                "compatibilityPageURL": spec["url"],
                "compatibilityPagePublished": spec["published"],
                "listedModelNames": names,
                "appleSiliconBlanket": spec.get("appleSiliconBlanket"),
                "hasPerModelCompatibilityPage": True,
                "download": download_record(spec["id"]),
            }
        )

    for release_id, raw in DOWNLOADS.items():
        if any(item["id"] == release_id for item in releases):
            continue
        releases.append(
            {
                "id": release_id,
                "marketingName": raw["marketingName"],
                "latestBuild": raw["latestBuild"],
                "latestBuildSourceURL": "https://support.apple.com/en-us/109033",
                "latestBuildSourcePublished": "October 26, 2026",
                "compatibilityPageURL": None,
                "compatibilityPagePublished": None,
                "listedModelNames": [],
                "appleSiliconBlanket": None,
                "hasPerModelCompatibilityPage": False,
                "download": download_record(release_id),
            }
        )

    catalog = {
        "retrieved": "2026-11-06",
        "product": "macOS Manager",
        "statement": (
            "Facts below were read from public Apple Support pages on 2026-11-06. "
            "A model is listed for a macOS version only when its exact Apple model name appears on that version's compatibility page. "
            "Factory macOS is not on these identify pages and is omitted. "
            "A published download link is not a statement that Software Update currently offers that installer for a particular Mac."
        ),
        "models": models,
        "releases": releases,
        "rules": {
            "appleSiliconArticleURL": "https://support.apple.com/en-us/116943",
            "appleSiliconArticlePublished": "May 12, 2026",
            "t2ArticleURL": "https://support.apple.com/en-us/103265",
            "t2ArticlePublished": "May 27, 2026",
            "bootableInstallerArticleURL": "https://support.apple.com/en-us/101578",
            "bootableInstallerArticlePublished": "September 14, 2026",
            "downloadArticleURL": "https://support.apple.com/en-us/102662",
            "downloadArticlePublished": "September 14, 2026",
            "softwareUpdateHelpURL": "https://support.apple.com/guide/mac-help/software-update-settings-on-mac-mchla7037245/mac",
            "softwareUpdateSettingsURL": "x-help-action://openPrefPane?bundleId=com.apple.Software-Update-Settings.extension",
            "upgrade27URL": "https://support.apple.com/en-us/127455",
            "voiceOverGuideURL": "https://support.apple.com/guide/voiceover/turn-voiceover-on-or-off-vo2682/mac",
            "appStoreGuidelinesURL": "https://developer.apple.com/app-store/review/guidelines/",
            "appStoreGuidelinesUpdated": "October 16, 2026",
        },
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    identifiers = {}
    for model in models:
        for ident in model["identifiers"]:
            identifiers.setdefault(ident, []).append(model["name"])
    shared = {key: value for key, value in identifiers.items() if len(value) > 1}
    print(f"models={len(models)} releases={len(releases)} sharedIdentifiers={len(shared)}")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
