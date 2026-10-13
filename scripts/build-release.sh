#!/bin/bash
set -euo pipefail

# Full resource build. Never substitute previously compiled shaders or icons.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${sdk_version%%.*}" -lt 27 ]]; then
  echo "PeakGlow requires macOS SDK 27 or later; found $sdk_version." >&2
  exit 1
fi
if ! xcrun --sdk macosx metal --version; then
  echo "Install the Metal Toolchain in Xcode Components or run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/peakglow-release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
xcodebuild -project PeakGlow.xcodeproj -scheme PeakGlow -configuration Release \
  -derivedDataPath "$staging/DerivedData" CODE_SIGNING_ALLOWED=NO build
app="$staging/PeakGlow.app"
ditto "$staging/DerivedData/Build/Products/Release/PeakGlow.app" "$app"
plist="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")"
minimum="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$plist")"
[[ "$minimum" == "27.0" ]]
[[ "$(lipo -archs "$app/Contents/MacOS/PeakGlow")" == "arm64" ]]
[[ -s "$app/Contents/Resources/default.metallib" ]]
[[ -s "$app/Contents/Resources/Assets.car" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconName' "$plist")" == "AppIcon" ]]
recorded_sdk="$(otool -l "$app/Contents/MacOS/PeakGlow" | awk '/LC_BUILD_VERSION/{found=1} found && $1=="sdk"{print $2; found=0}')"
[[ "$recorded_sdk" == "$sdk_version" ]]

# Clear file-provider/Finder attributes only in this temporary packaging copy.
/usr/bin/xattr -cr "$app"
codesign --force --options runtime --sign "${PEAKGLOW_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
archive="PeakGlow-$version-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/$archive"
ditto -x -k "$staging/$archive" "$staging/verification"
codesign --verify --deep --strict "$staging/verification/PeakGlow.app"
output="$repo_root/build/release/v$version"
mkdir -p "$output"
cp "$staging/$archive" "$output/$archive"
(cd "$output" && shasum -a 256 "$archive" > SHA256SUMS.txt)
echo "Packaged PeakGlow $version (Build $build_number): $output/$archive"
echo "Signing identity: ${PEAKGLOW_SIGN_IDENTITY:--}. Notarization has not been performed."
