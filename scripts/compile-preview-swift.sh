#!/bin/bash
set -euo pipefail
# Direct-build fallback: explicitly record the SDK version for system UI adoption.
# The minimum supported OS and the SDK used to build are separate values.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${1:?Usage: compile-preview-swift.sh /absolute/output/path}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
swift_compiler="$(xcrun --find swiftc)"
source_files=()
while IFS= read -r source_path; do source_files+=("$source_path"); done < <(find "$repo_root/PeakGlow" -name '*.swift' -type f | sort)
"$swift_compiler" -Xfrontend -disable-sandbox -sdk "$sdk_path" \
  -target arm64-apple-macosx14.0 \
  -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$sdk_version" \
  -module-cache-path "${TMPDIR:-/tmp}/peakglow-module-cache" -O \
  "${source_files[@]}" -o "$output_path"
# Fail packaging if the linked-on SDK fell back to the deployment target.
recorded_sdk="$(otool -l "$output_path" | awk '/LC_BUILD_VERSION/{found=1} found && $1=="sdk"{print $2; found=0}')"
if [[ "$recorded_sdk" != "$sdk_version" ]]; then
  echo "SDK metadata mismatch: expected $sdk_version, got $recorded_sdk" >&2
  exit 1
fi
