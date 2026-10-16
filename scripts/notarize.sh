#!/bin/bash
set -euo pipefail

# Build, sign with Developer ID, notarize, staple and package PeakGlow as a ZIP and a DMG.
# The DMG opens to the app next to an Applications shortcut, so installing is one drag.
#
#   PEAKGLOW_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   PEAKGLOW_NOTARY_PROFILE="peakglow-notary" \
#     bash scripts/notarize.sh
#
# The notarytool profile is created once with `xcrun notarytool store-credentials`,
# so no password or key appears in this repository, the environment or the shell history.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

identity="${PEAKGLOW_SIGN_IDENTITY:-}"
profile="${PEAKGLOW_NOTARY_PROFILE:-}"
if [[ -z "$identity" || -z "$profile" ]]; then
  echo "Set PEAKGLOW_SIGN_IDENTITY (a Developer ID Application identity) and PEAKGLOW_NOTARY_PROFILE." >&2
  exit 1
fi

echo "Checking the signing identity and notary credentials..."
if ! security find-identity -v -p codesigning | grep -F -q "$identity"; then
  echo "Signing identity not found in the keychain: $identity" >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$profile" > /dev/null 2>&1; then
  echo "notarytool cannot use the keychain profile '$profile'. Create it with: xcrun notarytool store-credentials" >&2
  exit 1
fi

# Full resource build; signs with the hardened runtime and a secure timestamp.
bash scripts/build-release.sh

version="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' PeakGlow.xcodeproj/project.pbxproj | head -1)"
[[ -n "$version" ]] || { echo "Could not read MARKETING_VERSION from the Xcode project." >&2; exit 1; }
output="$repo_root/build/release/v$version"
archive_name="PeakGlow-$version-macOS-arm64.zip"
archive="$output/$archive_name"
[[ -f "$archive" ]] || { echo "Expected package not found: $archive" >&2; exit 1; }

echo "Submitting $archive_name for notarization (this waits for Apple's result)..."
submit_log="$(mktemp)"
xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait 2>&1 | tee "$submit_log"
if ! grep -q "status: Accepted" "$submit_log"; then
  id="$(awk '/^ *id:/ {print $2; exit}' "$submit_log")"
  echo "Notarization was not accepted. Fetch the log with:" >&2
  echo "  xcrun notarytool log $id --keychain-profile $profile" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -x -k "$archive" "$work"
app="$work/PeakGlow.app"

xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose "$app"

# Replace the unstapled archive with the stapled one and refresh the checksum.
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/$archive_name"
cp "$work/$archive_name" "$archive"
(cd "$output" && shasum -a 256 "$archive_name" > SHA256SUMS.txt)

# Disk image: the stapled app beside an Applications shortcut. The image itself is signed,
# notarized and stapled so it opens without a Gatekeeper warning, also offline.
dmg_name="PeakGlow-$version-macOS-arm64.dmg"
stage="$work/dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/PeakGlow.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "PeakGlow $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$work/$dmg_name" > /dev/null
codesign --sign "$identity" --timestamp "$work/$dmg_name"

echo "Submitting $dmg_name for notarization..."
dmg_log="$(mktemp)"
xcrun notarytool submit "$work/$dmg_name" --keychain-profile "$profile" --wait 2>&1 | tee "$dmg_log"
if ! grep -q "status: Accepted" "$dmg_log"; then
  id="$(awk '/^ *id:/ {print $2; exit}' "$dmg_log")"
  echo "The disk image was not accepted. Fetch the log with:" >&2
  echo "  xcrun notarytool log $id --keychain-profile $profile" >&2
  exit 1
fi
xcrun stapler staple "$work/$dmg_name"
xcrun stapler validate "$work/$dmg_name"
spctl --assess --type open --context context:primary-signature --verbose "$work/$dmg_name"
cp "$work/$dmg_name" "$output/$dmg_name"
(cd "$output" && shasum -a 256 "$archive_name" "$dmg_name" > SHA256SUMS.txt)

echo "Notarized and stapled PeakGlow $version: $archive and $output/$dmg_name"
cat "$output/SHA256SUMS.txt"
