# Developer ID signing and notarization

Direct distribution outside the Mac App Store needs a Developer ID signature and Apple notarization. Without both, macOS Gatekeeper restricts first launch. The published releases are currently ad-hoc signed and not notarized.

This is a procedure for the maintainer. It has not been run yet. It requires a paid Apple Developer Program membership.

## Prerequisites

1. Apple Developer Program membership for the maintainer's team.
2. A **Developer ID Application** certificate installed in the login keychain. Confirm with:

   ```sh
   security find-identity -v -p codesigning
   ```

3. An App Store Connect API key or an app-specific password, stored as a notarytool keychain profile so no secret appears in the repository or shell history:

   ```sh
   xcrun notarytool store-credentials "peakglow-notary" \
     --apple-id "<apple id>" --team-id "<team id>"
   ```

   The command prompts for the app-specific password.

## Build a signed package

```sh
PEAKGLOW_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
  bash scripts/build-release.sh
```

With an identity set, the script signs with the hardened runtime and a secure timestamp, which notarization requires. With no identity it keeps ad-hoc signing.

## Notarize and staple

The script's ZIP is not stapled. Notarize it, staple the app, then rebuild the ZIP and checksum.

```sh
cd build/release/v<version>
xcrun notarytool submit PeakGlow-<version>-macOS-arm64.zip \
  --keychain-profile "peakglow-notary" --wait

mkdir stapling && ditto -x -k PeakGlow-<version>-macOS-arm64.zip stapling
xcrun stapler staple stapling/PeakGlow.app
xcrun stapler validate stapling/PeakGlow.app
spctl --assess --type execute --verbose stapling/PeakGlow.app

ditto -c -k --sequesterRsrc --keepParent stapling/PeakGlow.app PeakGlow-<version>-macOS-arm64.zip
shasum -a 256 PeakGlow-<version>-macOS-arm64.zip > SHA256SUMS.txt
```

If `notarytool` reports `Invalid`, fetch the log with `xcrun notarytool log <submission-id> --keychain-profile "peakglow-notary"`.

## After notarization

- Upload the rebuilt ZIP and `SHA256SUMS.txt` to the GitHub release.
- Update the README download note, which currently says the app is not notarized.
- Add a changelog entry that states what was actually verified (`stapler validate` and `spctl` results).

The notarized, unsandboxed build is a direct-distribution build only. It does not make the app eligible for the Mac App Store; see [Release audit](Release-Audit.md).
