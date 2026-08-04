#!/usr/bin/env python3

import hashlib
import json
import pathlib
import re
import sys
import urllib.request

CDN = "https://fonts.gstatic.com/s/e/notoemoji/latest/{codepoint}/lottie.json"

# Bundled: written into assets/emoji/ and shipped inside the app.
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

# Extended: NOT bundled. The app fetches these at runtime and checks them
# against the same digests, which live in kExtendedReactions. This script
# verifies the pins still describe what the CDN serves; it writes nothing.
EXTENDED = [
    ("1f525", "🔥", "96199d8e8fea7d90196b95b9a9e56b13af43e3817efe037bd9aa1e5215579838"),
    ("1f37f", "🍿", "8b48509721cf83b98946126f789178a289df6a67eef65690849ce0beec03d7a9"),
    ("1f923", "🤣", "da5832ec41e5b4b60a2668891bd0670c1495022096839b0b92d943cb85008aea"),
    ("1f60d", "😍", "2351f649844d0211f0935346c6358b7cdd38e7f2fb42164b7ecedbb67f7954aa"),
    ("1f92f", "🤯", "553f0131420995a5f7d989fa3e243ce57fe2620a34e4866c2adf1dd000aeeecf"),
    ("1f631", "😱", "159c6e05378b35fdb834c8981893162aad7935c3c7f52db5070caa0f47aca925"),
    ("1f973", "🥳", "6cc02b10d9471287c26b188d5a9b64899da86543fde29b60ed5e5caf69776c3d"),
    ("1f64c", "🙌", "a7f2d88118d720d0d1b68496561f8ef57e3a4e47c354b2bbdd53608784228b3f"),
    ("1f4af", "💯", "8e48b464d7473e94e7b744a1774f4c3b7c7a6892faee8667f9e555ddf5160798"),
    ("2764_fe0f", "❤️", "7925790edd7ec4a4da6ccb9491c61a2e03705182e7db263f12d8e46a8fcddb79"),
    ("1f440", "👀", "0dfcabf677099ebe20efacf98f680cf3aeac6f7b647228acda73917c65e2120f"),
    ("1f62d", "😭", "9f8b1a18099511d53356d870edd0e042323e0d2b023321ee144821e197f551ec"),
    ("1f480", "💀", "e0ce80dfbd957fb9c64c432c1d16ca6123f290e270688b0e23601099bfc2cc31"),
    ("1f634", "😴", "1fa14c30659503270104b54a7eefd082d7ebc039fc0bab280a6bd173fba3dcdd"),
    ("1f921", "🤡", "246c5aab976ccb17f5b7ef60ae27a1866d2a6f27bc082afc68923a55a7d83bcc"),
    ("1fae0", "🫠", "5d071c234038ddf15f6e14d3c40ab1b965dc3af4661f2c77c0ba41fc4d712e5c"),
]

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / "assets" / "emoji"
MANIFEST = ROOT / "lib" / "rooms" / "reactions.dart"

USAGE = """\
Refreshes assets/emoji/*.json — the Noto Animated Emoji (Lottie) the room's
quick reactions render — and verifies the digests the app uses to check the
*extended* set it fetches at runtime. The JSONs are build output: edit this
script, never them.

    python3 tool/fetch_reaction_emoji.py
    python3 tool/fetch_reaction_emoji.py --print-digests

Source is Google's noto-emoji-animation CDN, licensed CC BY 4.0 (attributed in
README.md). Every file is checked against the digest pinned above; a mismatch
aborts without writing, because these ship inside the app bundle and a silently
swapped animation is not something anyone would catch.

Only EMOJI is bundled. EXTENDED is verified and then discarded: those animations
are fetched by the app on demand and checked against the same digests, mirrored
in kExtendedReactions. A pin that drifts there does not break the app — the
reaction quietly falls back to its glyph — so this script is the only place the
drift is visible at all. Run it when reactions start rendering flat.

The CDN path says "latest", so a mismatch most likely means Google republished
that emoji rather than anything sinister. Re-pin deliberately: run
--print-digests, eyeball the size/frame-count delta it reports, then paste the
new digest into EMOJI/EXTENDED here *and* into lib/rooms/reactions.dart.
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


def check_digests_match_dart() -> bool:
    """The Dart manifest is the copy that actually guards the runtime fetch."""
    if not MANIFEST.exists():
        return True
    source = MANIFEST.read_text()
    pinned = dict(re.findall(r"codepoint: '([0-9a-f_]+)',\s*\n\s*label: '[^']*',\s*\n\s*digest: '([0-9a-f]{64})'", source))
    expected = {codepoint: digest for codepoint, _, digest in EXTENDED}
    if pinned == expected:
        return True
    for codepoint, digest in sorted(expected.items()):
        if codepoint not in pinned:
            print(f"  {MANIFEST.name} pins no digest for {codepoint}", file=sys.stderr)
        elif pinned[codepoint] != digest:
            print(
                f"  {MANIFEST.name} pins {pinned[codepoint]} for {codepoint}, "
                f"this script pins {digest}",
                file=sys.stderr,
            )
    for codepoint in sorted(set(pinned) - set(expected)):
        print(f"  {MANIFEST.name} pins {codepoint}, which this script does not verify", file=sys.stderr)
    return False


def check_manifest(codepoints: list[str]) -> bool:
    if not MANIFEST.exists():
        return True
    source = MANIFEST.read_text()
    referenced = set(re.findall(r"codepoint: '([0-9a-f_]+)'", source))
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

    for codepoint, glyph, expected in EMOJI + EXTENDED:
        bundled = any(codepoint == c for c, _, _ in EMOJI)
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
            print("  refusing to accept: this is not a playable Lottie", file=sys.stderr)
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

        if bundled:
            downloaded[codepoint] = raw

    if printing:
        return 1 if failed else 0
    if failed:
        print("\nNothing written — fix the failures above and re-run.", file=sys.stderr)
        return 1

    print()
    if not check_manifest([codepoint for codepoint, _, _ in EMOJI + EXTENDED]):
        print(
            f"\n{MANIFEST.name} and this script disagree about the reaction set. They must\n"
            "match exactly: the set here is what ships or is fetchable, and the set there\n"
            "is what the receive-side allow-list trusts.",
            file=sys.stderr,
        )
        return 1
    if not check_digests_match_dart():
        print(
            f"\n{MANIFEST.name} and this script disagree about the extended digests. The\n"
            "Dart copy is the one that actually guards the runtime fetch, so a drift here\n"
            "means the app is checking against something this script never verified.",
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
    print(
        f"\n{len(downloaded)} animations, {total / 1024:.0f} KB bundled; "
        f"{len(EXTENDED)} extended digests verified (not bundled)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
