#!/usr/bin/env bash
set -euo pipefail

: "${WINSPARKLE_DSA_PRIVATE_KEY:?the Windows signing key is not configured}"
: "${ED_SIGNATURE:?the macOS build job produced no EdDSA signature}"
: "${DMG_LENGTH:?the macOS build job produced no DMG length}"
: "${WINDOWS_VERSION:?}"
: "${MACOS_VERSION:?}"
: "${TAG:?}"
: "${REPO:?}"

if [ "$WINDOWS_VERSION" != "$MACOS_VERSION" ]; then
  echo "::error::the two build jobs disagree on the version ($WINDOWS_VERSION vs $MACOS_VERSION)"
  exit 1
fi

version="$WINDOWS_VERSION"
exe="PlayTogether-${version}-Windows.exe"
dmg="PlayTogether-${version}-macOS.dmg"

for artifact in "$exe" "$dmg"; do
  if [ ! -f "$artifact" ]; then
    echo "::error::$artifact is not in $(pwd) — the appcast would point at nothing"
    exit 1
  fi
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

dmg_length="$(wc -c < "$dmg" | tr -d ' ')"
if [ "$dmg_length" != "$DMG_LENGTH" ]; then
  echo "::error::the DMG is $dmg_length bytes but was signed at $DMG_LENGTH — the artifact changed in transit"
  exit 1
fi

echo "Verifying the macOS EdDSA signature against the app's own SUPublicEDKey"
public_ed_key="$(
  python3 -c "import plistlib;print(plistlib.load(open('macos/Runner/Info.plist','rb'))['SUPublicEDKey'])"
)"
python3 - "$public_ed_key" "$work/ed_pub.der" <<'PY'
import base64, sys
raw = base64.b64decode(sys.argv[1])
if len(raw) != 32:
    sys.exit(f"SUPublicEDKey decodes to {len(raw)} bytes, expected 32")
open(sys.argv[2], "wb").write(bytes.fromhex("302a300506032b6570032100") + raw)
PY
openssl pkey -pubin -inform DER -in "$work/ed_pub.der" -out "$work/ed_pub.pem"
printf '%s' "$ED_SIGNATURE" | base64 -d > "$work/ed_sig.bin"
if ! openssl pkeyutl -verify -rawin -pubin -inkey "$work/ed_pub.pem" \
  -sigfile "$work/ed_sig.bin" -in "$dmg" > /dev/null; then
  echo "::error::the DMG signature does not match SUPublicEDKey — SPARKLE_ED_PRIVATE_KEY and macos/Runner/Info.plist have drifted apart"
  exit 1
fi

echo "Signing $exe for WinSparkle"
printf '%s\n' "$WINSPARKLE_DSA_PRIVATE_KEY" > "$work/dsa_priv.pem"
chmod 600 "$work/dsa_priv.pem"
dsa_signature="$(
  openssl dgst -sha1 -binary < "$exe" \
    | openssl dgst -sha1 -sign "$work/dsa_priv.pem" \
    | openssl enc -base64 -A
)"
rm -f "$work/dsa_priv.pem"
if [ -z "$dsa_signature" ]; then
  echo "::error::signing $exe produced nothing"
  exit 1
fi

printf '%s' "$dsa_signature" | base64 -d > "$work/dsa_sig.bin"
if ! openssl dgst -sha1 -binary < "$exe" \
  | openssl dgst -sha1 -verify windows/runner/resources/dsa_pub.pem \
    -signature "$work/dsa_sig.bin" > /dev/null; then
  echo "::error::the installer signature does not match windows/runner/resources/dsa_pub.pem — WINSPARKLE_DSA_PRIVATE_KEY and the committed public key have drifted apart"
  exit 1
fi

base_url="https://github.com/${REPO}/releases/download/${TAG}"
notes_url="https://github.com/${REPO}/releases/tag/${TAG}"
feed_url="https://github.com/${REPO}/releases/latest/download/appcast.xml"
pub_date="$(date -R)"

cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>PlayTogether</title>
    <link>${feed_url}</link>
    <description>Updates for PlayTogether</description>
    <language>en</language>
    <item>
      <title>Version ${version}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${version}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>10.15</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>${notes_url}</sparkle:releaseNotesLink>
      <enclosure url="${base_url}/${dmg}"
                 sparkle:os="macos"
                 sparkle:edSignature="${ED_SIGNATURE}"
                 length="${dmg_length}"
                 type="application/octet-stream" />
    </item>
    <item>
      <title>Version ${version}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:releaseNotesLink>${notes_url}</sparkle:releaseNotesLink>
      <enclosure url="${base_url}/${exe}"
                 sparkle:os="windows"
                 sparkle:version="${version}"
                 sparkle:shortVersionString="${version}"
                 sparkle:dsaSignature="${dsa_signature}"
                 sparkle:installerArguments="/SILENT /SP- /NORESTARTAPPLICATIONS"
                 length="0"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

python3 -c "import xml.dom.minidom;xml.dom.minidom.parse('appcast.xml')"
echo "Wrote appcast.xml for ${version} (${TAG})"
