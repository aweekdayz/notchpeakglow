#!/bin/bash
set -euo pipefail

# Build, sign with Developer ID, notarize, staple and repackage PeakGlow.
#
#   PEAKGLOW_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   PEAKGLOW_NOTARY_PROFILE="peakglow-notary" \
#     bash scripts/notarize.sh
#
# The notarytool profile is created once with `xcrun notarytool store-credentials`,
# so no password or key appears in this repository, the environment or the shell history.
# This script has not been run against a real Apple Developer account yet.
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

echo "Notarized and stapled PeakGlow $version: $archive"
cat "$output/SHA256SUMS.txt"
