#!/usr/bin/env python3
"""Refreshes assets/ca/cacert.pem — the CA roots the app trusts in addition to
the ones the OS provides.

Run with: python3 tool/update_ca_bundle.py

The bundle is build output. Edit this script, never the .pem.

Source is curl.se's distribution of Mozilla's root program, which is the same
set every other toolchain means by "the CA bundle". It is fetched over HTTPS and
checked against the SHA-256 curl publishes beside it; a mismatch aborts without
touching the asset, because a silently corrupted trust store is worse than a
stale one.

This needs refreshing occasionally: roots expire and new ones are added. It is
purely additive at runtime (see lib/tls.dart), so a stale bundle degrades to
"the OS roots decide", which is exactly where the app was before it existed —
it can never make a connection fail that would otherwise have worked.
"""

import hashlib
import pathlib
import sys
import urllib.request

BUNDLE_URL = "https://curl.se/ca/cacert.pem"
SHA256_URL = "https://curl.se/ca/cacert.pem.sha256"
DEST = pathlib.Path(__file__).resolve().parent.parent / "assets" / "ca" / "cacert.pem"


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def main() -> int:
    print(f"Fetching {BUNDLE_URL}")
    bundle = fetch(BUNDLE_URL)

    # curl publishes "<hex>  cacert.pem"; only the digest matters here.
    expected = fetch(SHA256_URL).decode().split()[0].strip().lower()
    actual = hashlib.sha256(bundle).hexdigest()
    if actual != expected:
        print(f"SHA-256 mismatch!\n  expected {expected}\n  actual   {actual}", file=sys.stderr)
        return 1

    count = bundle.count(b"-----BEGIN CERTIFICATE-----")
    if count < 100:
        # A truncated download or an error page would otherwise be written out
        # as a "valid" bundle that quietly trusts almost nothing.
        print(f"Only {count} certificates found — refusing to write", file=sys.stderr)
        return 1

    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_bytes(bundle)
    print(f"Wrote {DEST} — {count} certificates, sha256 {actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
