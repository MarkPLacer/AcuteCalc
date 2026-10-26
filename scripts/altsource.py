#!/usr/bin/env python3
"""Builds the app source (apps.json) that AltStore, SideStore, Feather and eSign read.

One file serves all four: the `versions` array is the current AltStore format, and the newest
version is repeated in the flat fields (`version`, `versionDate`, `versionDescription`,
`downloadURL`, `size`) that eSign and older clients read. Version, build, size and SHA-256 come
from the IPA itself: AltStore and SideStore refuse an IPA that differs from its entry, so every
entry points to its own `AcuteCalc-<version>.ipa`, which a newer build never overwrites.

The app reads the same file to offer updates (AcuteCore/Updates/AppSourceFeed.swift).
"""

import argparse
import datetime
import hashlib
import json
import plistlib
import re
import struct
import sys
import zipfile
import zlib
from pathlib import Path

BUNDLE_ID = "com.markplacer.acutecalc"
WEBSITE = "https://github.com/MarkPLacer/AcuteCalc"
TINT = "1EA8FE"

SOURCE_SUBTITLE = "Namestitev in posodobitve aplikacije Acute Calc"
SOURCE_DESCRIPTION = (
    "Najnovejši build aplikacije Acute Calc z veje main. Vir se samodejno posodobi ob vsakem "
    "uspešnem buildu na GitHubu, zato AltStore, SideStore, Feather in eSign sami javijo novo "
    "različico."
)
APP_SUBTITLE = "Grafični kalkulator za maturo in 1. letnik"
APP_DESCRIPTION = """Sodoben grafični in znanstveni kalkulator za iPhone in iPad (iOS 27), narejen za učenje za splošno maturo iz matematike in fizike ter za prvi letnik na univerzi.

• Strukturiran vnos: ulomki, koreni, potence, integrali, limite, matrike, s točnimi rezultati
• Grafi 2D, 3D in v kompleksni ravnini (Metal 4, 120 Hz) s posebnimi točkami in analizo funkcij
• Enačbe, neenačbe in sistemi, odvodi in integrali
• Orodja: statistika in regresije, porazdelitve, trikotniki, vektorji, kombinatorika, pretvorniki, konstante CODATA
• Univerzitetna orodja: diferencialne enačbe, funkcije več spremenljivk, Fourierove vrste, vektorska analiza, nosilci, izmenična vezja, geodezija

Vse se računa na napravi, brez računov in nakupov – vse funkcije so odklenjene."""

PRIVACY_KEY = re.compile(r"NS\w*UsageDescription")
MAX_CHANGES = 30


def read_ipa(path):
    """Version, build, minimum iOS and privacy strings from the IPA's Info.plist files."""
    data = Path(path).read_bytes()
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        plists = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/(PlugIns/[^/]+\.appex/)?Info\.plist", n)]
        main = next(n for n in plists if "/PlugIns/" not in n)
        info = plistlib.loads(archive.read(main))
        privacy = {}
        for name in plists:
            for key, value in plistlib.loads(archive.read(name)).items():
                if PRIVACY_KEY.fullmatch(key):
                    privacy[key] = value
    if info["CFBundleIdentifier"] != BUNDLE_ID:
        sys.exit(f"unexpected bundle identifier {info['CFBundleIdentifier']}")
    return {
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "minimum_os": info.get("MinimumOSVersion"),
        "privacy": privacy,
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def icon_from_ipa(path):
    """The app's largest bundled icon as a standard PNG (the fallback when ictool fails).

    Xcode stores it as Apple's CgBI variant, which only Apple's decoder reads: a raw deflate
    stream of BGRA rows. The filters work per channel, so swapping blue and red in the filtered
    rows gives the RGBA image (an app icon is opaque, so its premultiplied alpha changes nothing).
    """
    icons = []
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            # The primary icon's files only (AppIcon60x60@2x.png, AppIcon76x76@2x~ipad.png),
            # never an alternate one such as AppIcon-Midnight.
            if re.fullmatch(r"Payload/[^/]+\.app/AppIcon\d+x\d+(@\dx)?(~ipad)?\.png", name):
                data = archive.read(name)
                width = struct.unpack(">I", data.split(b"IHDR", 1)[1][:4])[0]
                icons.append((width, data))
    if not icons:
        return None
    data = max(icons)[1]
    chunks, idat, cgbi, pos = [], b"", False, 8
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"CgBI":
            cgbi = True
        elif kind == b"iDOT":
            pass  # Apple's offsets into the IDAT data, which is recompressed below
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        else:
            chunks.append((kind, body))
    if not cgbi:
        return data
    width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if (depth, color, interlace) != (8, 6, 0):
        return None
    rows = bytearray(zlib.decompress(idat, -15))
    stride = width * 4 + 1
    for row in range(height):
        start = row * stride + 1
        rows[start:start + width * 4:4], rows[start + 2:start + width * 4:4] = (
            rows[start + 2:start + width * 4:4], rows[start:start + width * 4:4])

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    return (b"\x89PNG\r\n\x1a\n" + b"".join(chunk(k, b) for k, b in chunks)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


def slovenian_changes(n):
    if n % 100 == 1:
        return f"{n} sprememba"
    if n % 100 == 2:
        return f"{n} spremembi"
    if n % 100 in (3, 4):
        return f"{n} spremembe"
    return f"{n} sprememb"


def release_notes(path):
    """A bullet per commit subject, oldest first, as AltStore and Feather show plain text."""
    lines = []
    if path and Path(path).exists():
        lines = [line.strip() for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]
    if not lines:
        return "Manjše izboljšave."
    notes = [f"• {line}" for line in lines[:MAX_CHANGES]]
    if len(lines) > MAX_CHANGES:
        notes.append(f"… in še {slovenian_changes(len(lines) - MAX_CHANGES)}")
    return "\n".join(notes)


def previous_versions(path, base):
    """Earlier entries of this source whose own versioned IPA is still kept on the release."""
    if not path or not Path(path).exists():
        return []
    try:
        source = json.loads(Path(path).read_text(encoding="utf-8"))
    except ValueError:
        return []
    for app in source.get("apps", []):
        if app.get("bundleIdentifier") == BUNDLE_ID:
            return [
                v for v in app.get("versions", [])
                if v.get("downloadURL") == f"{base}/{asset_name(v.get('version', ''))}"
            ]
    return []


def asset_name(version):
    return f"AcuteCalc-{version}.ipa"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--download-base", required=True, help="URL of the release's download folder")
    parser.add_argument("--changes", help="commit subjects since the previous release, one per line")
    parser.add_argument("--previous", help="the source as published before this build")
    parser.add_argument("--keep", type=int, default=5, help="versions (and their IPAs) to keep")
    parser.add_argument("--date", help="ISO 8601 date of this build (default: now)")
    parser.add_argument("--output", required=True)
    parser.add_argument("--kept-assets", help="writes the versioned IPA names still referenced")
    parser.add_argument("--icon", help="the source's icon; written from the IPA when it is missing")
    args = parser.parse_args()

    base = args.download_base.rstrip("/")
    ipa = read_ipa(args.ipa)
    if args.icon and not Path(args.icon).exists():
        icon = icon_from_ipa(args.ipa)
        if icon:
            Path(args.icon).write_bytes(icon)
            print(f"{args.icon}: the IPA's own icon (ictool gave none)")
    date = args.date or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    latest = {
        "version": ipa["version"],
        "buildVersion": ipa["build"],
        "date": date,
        "localizedDescription": release_notes(args.changes),
        "downloadURL": f"{base}/{asset_name(ipa['version'])}",
        "size": ipa["size"],
        "sha256": ipa["sha256"],
    }
    if ipa["minimum_os"]:
        latest["minOSVersion"] = ipa["minimum_os"]

    earlier = [
        v for v in previous_versions(args.previous, base)
        if v.get("version") != latest["version"] and v.get("buildVersion") != latest["buildVersion"]
    ]
    versions = [latest] + earlier[: max(args.keep - 1, 0)]

    app = {
        "name": "Acute Calc",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": "MarkPLacer",
        "subtitle": APP_SUBTITLE,
        "localizedDescription": APP_DESCRIPTION,
        "iconURL": f"{base}/AcuteCalc-icon.png",
        "tintColor": TINT,
        "category": "utilities",
        "versions": versions,
        "appPermissions": {"entitlements": [], "privacy": ipa["privacy"]},
        # Flat copy of the newest version for eSign and older clients ("type" 1 is an app in eSign).
        "version": latest["version"],
        "versionDate": latest["date"],
        "versionDescription": latest["localizedDescription"],
        "downloadURL": latest["downloadURL"],
        "size": latest["size"],
        "type": 1,
    }
    source = {
        "name": "Acute Calc",
        "identifier": f"{BUNDLE_ID}.source",
        "subtitle": SOURCE_SUBTITLE,
        "description": SOURCE_DESCRIPTION,
        "iconURL": app["iconURL"],
        "website": WEBSITE,
        "sourceURL": f"{base}/apps.json",
        "tintColor": TINT,
        "featuredApps": [BUNDLE_ID],
        "apps": [app],
        "news": [],
    }

    Path(args.output).write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.kept_assets:
        names = [asset_name(v["version"]) for v in versions]
        Path(args.kept_assets).write_text("\n".join(names) + "\n", encoding="utf-8")
    print(f"{asset_name(latest['version'])}: build {latest['buildVersion']}, {latest['size']} bytes, "
          f"{len(versions)} version(s) in the source")


if __name__ == "__main__":
    main()
