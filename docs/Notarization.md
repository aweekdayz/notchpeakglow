# Developer ID signing and notarization

Direct distribution outside the Mac App Store needs a Developer ID signature and Apple notarization. Without both, macOS Gatekeeper restricts first launch, which most users will not work around. Releases from 1.7.1 are signed and notarized with this procedure; earlier releases are ad-hoc signed and not notarized.

This is a procedure for the maintainer. It has been run end to end for 1.7.1 (and first as a dry run on the 1.7.0 source, which Apple accepted). Apple's enrollment steps and fees change, so check the linked Apple pages before relying on the details below.

## 1. Enroll and create credentials (one time)

1. Join the Apple Developer Program as an individual or organization: <https://developer.apple.com/programs/enroll/>. It is a paid annual membership, requires an Apple Account with two-factor authentication, and identity verification can take from hours to days.
2. In Xcode, open Settings → Accounts, sign in, select the team and choose Manage Certificates. Add a **Developer ID Application** certificate. Only the Account Holder can create it. Confirm it is installed:

   ```sh
   security find-identity -v -p codesigning
   ```

   Note the full identity name, for example `Developer ID Application: Name (TEAMID)`.
3. Create an app-specific password for your Apple Account at <https://account.apple.com> (or use an App Store Connect API key). Find your Team ID in the membership details. Store them as a notarytool keychain profile so no secret appears in the repository, the environment or the shell history:

   ```sh
   xcrun notarytool store-credentials "peakglow-notary" \
     --apple-id "<apple id>" --team-id "<team id>"
   ```

   The command prompts for the password. Never paste it into a chat, an issue or a commit.

## 2. Build, notarize and package (each release)

```sh
PEAKGLOW_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
PEAKGLOW_NOTARY_PROFILE="peakglow-notary" \
  bash scripts/notarize.sh
```

The script:

1. Checks that the identity and notary profile exist.
2. Runs `scripts/build-release.sh`, which signs with the hardened runtime and a secure timestamp when `PEAKGLOW_SIGN_IDENTITY` is set (ad-hoc builds are unchanged without it).
3. Submits the ZIP with `notarytool` and waits. If Apple rejects it, the script stops and prints the command to fetch the log.
4. Staples the ticket to the app, validates it, runs `codesign --verify` and `spctl --assess`.
5. Replaces the ZIP and `SHA256SUMS.txt` in `build/release/v<version>/` with the stapled archive.

## 3. Check and publish

- Extract the final ZIP on a Mac that has not seen the app and confirm it opens without the Gatekeeper warning.
- Upload the ZIP and `SHA256SUMS.txt` to the GitHub release.
- Update the README download note, which currently says the app is not notarized, and the release notes.
- Add a changelog entry that states what was actually verified (the `stapler validate` and `spctl` results).

The notarized, unsandboxed build is a direct-distribution build only. It does not make the app eligible for the Mac App Store; see [Release audit](Release-Audit.md).

## 4. Updates (Sparkle)

The app checks `appcast.xml` on `main` (served from raw.githubusercontent.com) about once a day. Each release adds one entry, signed with the Sparkle EdDSA key. The matching public key is in `PeakGlow/Info.plist` as `SUPublicEDKey`; the private key is in the maintainer's login keychain (item "https://sparkle-project.org"). **Back it up** (`generate_keys -x file`, stored somewhere safe and never in this repository): if it is lost, installed copies can no longer verify updates and people would have to download a new version by hand once.

For each release, after `scripts/notarize.sh` has built the DMG and before the GitHub release is published:

```sh
SPARKLE_BIN=/path/to/Sparkle/bin bash scripts/update-appcast.sh [notes.html]
```

`SPARKLE_BIN` is the `bin` folder of the Sparkle release tarball (it holds `sign_update`). Commit the changed `appcast.xml` to `main` in the same release, and publish the GitHub release with the DMG as an asset named in the entry. For a test release set `PEAKGLOW_CHANNEL=beta`: the entry is on the `beta` channel and people on the stable channel are never offered it.

Sparkle is embedded in the app, so `scripts/build-release.sh` signs its helpers, the framework and the app in that order with the same identity; notarization rejects the app otherwise.
