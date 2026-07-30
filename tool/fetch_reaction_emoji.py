#!/usr/bin/env python3

import hashlib
import json
import pathlib
import re
import sys
import urllib.request

CDN = "https://fonts.gstatic.com/s/e/notoemoji/latest/{codepoint}/lottie.json"

EMOJI = [
    ("1f496", "💖", "71614ccf8c7fe4c3be20691c0e2ffc5c5f7beaf306a3b485a6f0f1b2b71d7339"),
    ("1f44d", "👍", "a5803c4978c0760977aa08033ab0abcb5023945a47008261cd405815fc947698"),
    ("1f389", "🎉", "eab1fd7070bffd2965c12a80d2d91cff76683af65019f142acf9a553ee877b5c"),
    ("1f44f", "👏", "fc1d22422ac8ce686e9851ea69410d43dc7d244cc9c3a33cc768ffd2653a79e3"),
    ("1f602", "😂", "ae479405485961c5c233d882bd2b8ddf54c24e7ddb48371e6346b04b6b57edca"),
    ("1f62e", "😮", "daa0118bbc4f628aaabde5b0c96ebf3980c7aca265700bb0da809cb9f4d0ffbd"),
    ("1f622", "😢", "58c4605cb7cae240597ebea1bb0cba87d592aea24b988e0f3cc48f39f045c2fb"),
    ("1f914", "🤔", "46405d972ad78a2fc917fa8e5786b0ebcdfdf644114be3c0941b98cb7e1c47c5"),
]

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / "assets" / "emoji"
MANIFEST = ROOT / "lib" / "rooms" / "reactions.dart"

USAGE = """\
Refreshes assets/emoji/*.json — the Noto Animated Emoji (Lottie) the room's
quick reactions render. The JSONs are build output: edit this script, never
them.

    python3 tool/fetch_reaction_emoji.py
    python3 tool/fetch_reaction_emoji.py --print-digests

Source is Google's noto-emoji-animation CDN, licensed CC BY 4.0 (attributed in
README.md). Each file is checked against the digest pinned above; a mismatch
aborts without writing, because these ship inside the app bundle and a silently
swapped animation is not something anyone would catch.

The CDN path says "latest", so a mismatch most likely means Google republished
that emoji rather than anything sinister. Re-pin deliberately: run
--print-digests, eyeball the size/frame-count delta it reports, then paste the
new digest into EMOJI above.
"""


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def describe(raw: bytes) -> str:
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as error:
        return f"not valid JSON ({error})"
    return (
        f"{len(raw)} bytes, {doc.get('w')}x{doc.get('h')}, "
        f"{doc.get('op')} frames @ {doc.get('fr')} fps, "
        f"{len(doc.get('layers') or [])} layers"
    )


def usable(raw: bytes) -> bool:
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError:
        return False
    return bool(doc.get("layers")) and bool(doc.get("op")) and bool(doc.get("fr"))


def check_manifest(codepoints: list[str]) -> bool:
    if not MANIFEST.exists():
        return True
    source = MANIFEST.read_text()
    referenced = set(re.findall(r"codepoint: '([0-9a-f]+)'", source))
    expected = set(codepoints)
    if referenced == expected:
        return True
    if not referenced:
        print(
            f"  found no `codepoint: '…'` entries in {MANIFEST.name} at all — if the\n"
            "  manifest was restructured, this check needs restructuring with it",
            file=sys.stderr,
        )
    for missing in sorted(expected - referenced):
        print(f"  {MANIFEST.name} never declares {missing}", file=sys.stderr)
    for extra in sorted(referenced - expected):
        print(f"  {MANIFEST.name} declares {extra}, which this script does not fetch", file=sys.stderr)
    return False


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(USAGE)
        return 0
    printing = "--print-digests" in argv

    downloaded: dict[str, bytes] = {}
    failed = False

    for codepoint, glyph, expected in EMOJI:
        url = CDN.format(codepoint=codepoint)
        print(f"{glyph}  {url}")
        try:
            raw = fetch(url)
        except Exception as error:
            print(f"  download failed: {error}", file=sys.stderr)
            failed = True
            continue

        actual = hashlib.sha256(raw).hexdigest()
        print(f"  {describe(raw)}")

        if printing:
            print(f'  ("{codepoint}", "{glyph}", "{actual}"),')
            continue

        if not usable(raw):
            print("  refusing to write: this is not a playable Lottie", file=sys.stderr)
            failed = True
            continue
        if actual != expected:
            print(
                f"  SHA-256 mismatch — expected {expected}, got {actual}\n"
                "  Re-run with --print-digests and re-pin deliberately.",
                file=sys.stderr,
            )
            failed = True
            continue

        downloaded[codepoint] = raw

    if printing:
        return 1 if failed else 0
    if failed:
        print("\nNothing written — fix the failures above and re-run.", file=sys.stderr)
        return 1

    print()
    if not check_manifest([codepoint for codepoint, _, _ in EMOJI]):
        print(
            f"\n{MANIFEST.name} and this script disagree about the reaction set. They must\n"
            "match exactly: the set here is what ships, and the set there is what the\n"
            "receive-side allow-list trusts.",
            file=sys.stderr,
        )
        return 1

    DEST.mkdir(parents=True, exist_ok=True)
    for name in DEST.glob("*.json"):
        if name.stem not in downloaded:
            name.unlink()
            print(f"Removed {name.relative_to(ROOT)} — no longer in the set")
    for codepoint, raw in downloaded.items():
        target = DEST / f"{codepoint}.json"
        target.write_bytes(raw)
        print(f"Wrote {target.relative_to(ROOT)}")

    total = sum(len(raw) for raw in downloaded.values())
    print(f"\n{len(downloaded)} animations, {total / 1024:.0f} KB bundled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
