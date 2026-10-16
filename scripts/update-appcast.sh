#!/bin/bash
set -euo pipefail

# Add the release in build/release/v<version> to appcast.xml, signed with the Sparkle EdDSA key.
#
#   SPARKLE_BIN=/path/to/Sparkle/bin bash scripts/update-appcast.sh [path/to/notes.html]
#
# SPARKLE_BIN holds Sparkle's `sign_update` (from the Sparkle release tarball). The private key
# stays in the login keychain, where `generate_keys` put it; it is never written to this repository.
# Set PEAKGLOW_CHANNEL=beta for a test release: only people who opt in to that channel are offered it.
# Run it after the DMG is built and before the release is published, then commit appcast.xml to main
# in the same release; the app reads it from raw.githubusercontent.com.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

sparkle_bin="${SPARKLE_BIN:-}"
[ -x "$sparkle_bin/sign_update" ] || { echo "Set SPARKLE_BIN to Sparkle's bin directory (it must contain sign_update)." >&2; exit 1; }

version="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' PeakGlow.xcodeproj/project.pbxproj | head -1)"
build="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' PeakGlow.xcodeproj/project.pbxproj | head -1)"
minimum="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' PeakGlow/Info.plist)"
tag="v$version"
channel="${PEAKGLOW_CHANNEL:-}"
[ "$channel" = "beta" ] && tag="v$version-beta"
dmg="build/release/v$version/PeakGlow-$version-macOS-arm64.dmg"
[ -f "$dmg" ] || { echo "Missing $dmg. Run scripts/notarize.sh first." >&2; exit 1; }
notes_file="${1:-}"

signature="$("$sparkle_bin/sign_update" "$dmg")"   # sparkle:edSignature="…" length="…"
url="https://github.com/aweekdayz/notchpeakglow/releases/download/$tag/$(basename "$dmg")"

python3 - "$version" "$build" "$minimum" "$url" "$signature" "$channel" "$notes_file" <<'PY'
import sys, email.utils, html
version, build, minimum, url, signature, channel, notes_file = sys.argv[1:8]
if any(f'sparkle:version>{build}<' in l for l in open('appcast.xml')):
    sys.exit(f'appcast.xml already has build {build}.')
notes = ''
if notes_file:
    notes = f'\n      <description><![CDATA[{open(notes_file).read()}]]></description>'
chan = f'\n      <sparkle:channel>{channel}</sparkle:channel>' if channel else ''
item = f'''    <item>
      <title>PeakGlow {html.escape(version)}</title>
      <pubDate>{email.utils.formatdate(localtime=False)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>{chan}{notes}
      <enclosure url="{url}" {signature} type="application/octet-stream"/>
    </item>
'''
s = open('appcast.xml').read()
marker = '    <language>en</language>\n'
assert marker in s
open('appcast.xml', 'w').write(s.replace(marker, marker + item, 1))
print('Added', version, 'build', build, 'to appcast.xml')
PY
