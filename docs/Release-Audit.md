# Release audit — October 12, 2026

Historical audit of 1.6.1 / Build 38 (never published separately; its changes shipped in 1.6.2). **Current public release: 1.7.5 / Build 49** — see the follow-up sections below, which supersede earlier status lines.

## Checks completed

All application Swift and Metal source files, bundle metadata, Xcode project, project-generation configuration, shell scripts, current README, development notes and HIG history were reviewed. The user-approved Glow appearance and native selector were preserved.

| Area | Finding and action |
| --- | --- |
| Language | UI strings were English, but diagnostic logs, comments and README were not. All current tracked text is now English. Error messages no longer interpolate potentially localized system descriptions. Native system menus/dialogs follow macOS language. |
| Build consistency | Project and generator agreed on version 1.6.1, Build 38 at the time of this audit (now 1.6.2, Build 39), macOS 27, arm64 and hardened runtime. English is explicit in the bundle and target. |
| Resource completeness | Added a full Xcode packaging script. It requires a freshly built metallib and compiled layered-icon assets instead of reusing a prior preview's resources. |
| Screen geometry | Require a built-in display and positive notch bounds. Detect recognized Pro size using physical display dimensions, independent of scaled resolution. Unknown products remain unknown. |
| Display lifecycle | Stop hidden rendering on display loss/sleep, refresh EDR headroom after reposition, restore pending alert state and dismiss controls when geometry changes. |
| Missing power | Valid zero readings remain valid. Missing data clears the pending dwell, averaging window and stale automatic load. Driver connections can retry after failure. |
| Temperature | Validate driver result, float type and byte length; cache successful metadata, retry failed connections, clear missing-data dwell and stale alerts, release the connection on deinitialization. Remove unused threshold fields. Unknown families use system critical state only. |
| Preferences | Preserve custom thresholds and approved visual parameters. Clear an alert persisted by the previous process at startup. |
| Discoverability | If no notch display is available at launch, show Settings. A request for controls without a notch opens Settings; Finder reopening also opens Settings. |
| Interface | Preserve native sliders and segmented control, fixed panel layout, upper-right Reset, interruptible animation and pointer dismissal after clicking. Add accurate device support explanation. Restrict alert brightness to the shader's actual 0.5–2× range; larger values previously had no additional visual effect. |
| Attribution | Identify the original project and its SMC reference. The upstream README declares MIT, but the repository has no `LICENSE` file (GitHub reports `license: null`), so there is no copyright line or license text. |

## Build evidence

- Optimized direct Swift compilation against the macOS 27 SDK, targeting arm64 macOS 27, passed.
- Linked SDK and minimum-system metadata guards passed.
- Shell syntax, property-list syntax, whitespace and non-English-source scans passed.
- In the restricted runner, default Metal component discovery misleadingly reported a missing toolchain; its installed Apple compiler and linker successfully compiled the current shader when selected directly.
- The restricted full build then failed at native layered-icon export, including from a cleaned temporary icon copy.
- The user ran the same release script in their normal terminal. An initial Bash 3.2 empty-array/nounset error was corrected; default and explicit-toolchain argument assembly were checked using the system Bash.
- On October 12 at approximately 23:20 local time, the user reported `BUILD SUCCEEDED` and successful packaging of 1.6.1 / Build 38. No icon source change was necessary between the restricted export failure and the successful normal-terminal build.
- The resulting ZIP was extracted and independently inspected: it contains the freshly compiled `default.metallib`, compiled `Assets.car` and `AppIcon.icns`; the plist declares `CFBundleIconName=AppIcon`, English, version 1.6.1, Build 38 and macOS 27.
- Its executable is arm64 with linked SDK 27.0 and minimum OS 27.0. Strict deep signature verification and the archive SHA-256 check passed. The signature is ad-hoc with hardened runtime and no TeamIdentifier; it is not Developer ID-signed or Apple-notarized.
- No application was launched for interactive testing, and no physical-device matrix or energy benchmark was performed.

The previous 1.6.0 package signature and checksum were verified during publication. The 1.6.1 package has now been independently checked as described above; it was not published on its own; its changes shipped in 1.6.2.

## Hardware coverage

The implementation accommodates notched Air and Pro families, Retina scale, variable notch geometry, non-primary built-in displays and dynamic EDR headroom. This is not evidence that every M-series chip works. PSTR and Tp* sensor availability can differ between devices and operating systems.

Pending user hardware checks: 13/15-inch Air; 14/16-inch Pro; scaled resolutions; external primary display with the lid open; disconnect/reconnect and closed-display mode; screen sleep/wake; full-screen Spaces and Stage Manager; appearance and accessibility settings; sensor-unavailable behavior. The application only draws on the built-in notch display. Intel and desktop Macs are outside the arm64 notched-MacBook target.

Power presets remain 13/19 W for Air and 30/55 W for Pro/unknown. They are adjustable family defaults, not per-chip performance normalization. Temperature alerts are heuristics, not proof of throttling.

## Remaining release requirements

1. Full source/resource build and local packaging are complete. No further Metal Toolchain installation is required. Restricted runners can optionally use `PEAKGLOW_METAL_TOOLCHAIN` to select the mounted Apple compiler, but native icon export may still require a normal terminal environment.
2. Have the user assess the new application without claiming automated UI coverage.
3. Ask the upstream author to add the `LICENSE` file their README already declares (MIT), and confirm any relevant third-party obligations. Do not add a license on the upstream author's behalf. Needed before an App Store submission.
4. For normal direct public distribution, supply a Developer ID identity and complete Apple notarization. Current ad-hoc signing does not provide either.
5. For the Mac App Store, separately investigate the AppleSMC protocol, sandbox compatibility, signing and review requirements. The current unsandboxed configuration is not App Store-ready.

Xcode's interface is optional for routine command-line builds. Its installed compiler, SDK, Metal and asset tools are required; the Swift-only preview build omits resource compilation and cannot certify a full release.

## Maintainer identity follow-up — October 13, 2026

Current source: 1.6.2 / Build 39. On October 13 the user rebuilt it with the standard release script. The resulting 1.6.2 ZIP was independently extracted and verified: new bundle identifier and maintainer metadata, English, compiled shader and layered-icon assets, bundled Credits, strict signature and checksum. Signing remains ad-hoc with hardened runtime and no Developer ID or notarization. The ZIP and checksum were published as the latest GitHub release, v1.6.2, on October 13 at the user's explicit request. Original licensing status remains unchanged.

Project presentation and bundle metadata identify aweekdayz as maintainer. The identifier is `com.aweekdayz.peakglow`; the previous namespace is referenced only by a one-time, allowlisted preference migration. A focused migration check confirmed that new settings win, unknown keys and transient alerts are excluded, and a false Boolean value is preserved. The check does not modify user defaults.

A native About panel reads the bundled Credits.rtf. RTF parsing, plist/project syntax, resource references and optimized Swift compilation passed. No application was launched for UI testing. Credits acknowledge provenance without assigning the original code's copyright to the maintainer; unresolved redistribution permission remains explicit.

## 1.6.3 follow-up — October 13, 2026

Build 40 adds sample-gap continuity for temperature and load detection, clamps stored timing settings, adopts the Swift 6 language mode, completes the menu bar and shows the menu bar while Settings is open. The ZIP was built with `scripts/build-release.sh` and its extracted contents were inspected: version 1.6.3 / Build 40, `com.aweekdayz.peakglow`, arm64, SDK and minimum OS 27.0, English, compiled shader, layered icon and Credits resources, strict signature validation and checksum. Signing is ad-hoc with hardened runtime; there is no Developer ID signature or notarization (see [Notarization](Notarization.md)). The maintainer tested the package on a Mac. Hardware coverage across models and display configurations, sleep/wake behavior on other Macs, upstream redistribution permission and App Store eligibility remain unverified or unresolved.

## 1.6.4 follow-up — October 13, 2026

Build 41 adds a menu bar icon whose menu shows system power, offers the Glow modes with a checkmark on the current one, and opens Settings or Quit (it can be turned off in Settings → Behavior). It removes the Show PeakGlow Controls command and its shortcut, uses system text styles in the controls panel (the power readout is 26 pt instead of a fixed 30 pt) and reorders Settings → Behavior. The ZIP was built with `scripts/build-release.sh` and its extracted contents were inspected: version 1.6.4 / Build 41, `com.aweekdayz.peakglow`, arm64, SDK and minimum OS 27.0, strict signature validation and checksum. Signing is ad-hoc with hardened runtime; there is no Developer ID signature or notarization. The maintainer tested the package on a Mac. VoiceOver reading order, Full Keyboard Access focus order and Increase Contrast appearance were not independently verified. Upstream redistribution permission and App Store eligibility remain unresolved.

## 1.6.5 follow-up — October 13, 2026

Build 42 redraws the glow shader to follow the hardware notch silhouette (flat top merged with the screen edge, rounded lower corners) and shows power continuously: the color moves along one hue direction (blue, cyan, green, yellow) while brightness (0.55x to 1.35x) and bloom width (0.65x to 1.45x) grow with power. The position on the ramp is mapped around the two Power thresholds and smoothed; Soft and Boost previews use fixed positions, and orange and red stay reserved for the temperature warning. The ZIP was built with `scripts/build-release.sh` and its extracted contents were inspected: version 1.6.5 / Build 42, arm64, SDK and minimum OS 27.0, compiled shader, strict signature validation and checksum. Signing is ad-hoc with hardened runtime; there is no Developer ID signature or notarization. The maintainer tested the package on a Mac. Before the build, the shader was rendered offscreen to still images and the power-to-position mapping was checked in isolation (monotone, bounded to 0...1). Appearance on light wallpapers, across all notched models and under accessibility settings was not independently verified. Upstream redistribution permission and App Store eligibility remain unresolved.

## 1.6.6 follow-up — October 13, 2026

Build 43 adds Copy Diagnostics to Settings → Appearance, a bug report template field and a README troubleshooting section. The report lists the PeakGlow version, macOS version, model, chip, family, notch display, power and temperature sensor status, thermal state, thresholds, Glow mode and menu bar icon, with no serial number or personal data. The ZIP was built with `scripts/build-release.sh` and its extracted contents were inspected: version 1.6.6 / Build 43, arm64, SDK and minimum OS 27.0, strict signature validation and checksum. Signing is ad-hoc with hardened runtime; there is no Developer ID signature or notarization. `scripts/notarize.sh` and the updated [Notarization](Notarization.md) steps are in the repository but have not been run against a real Apple Developer account.

First hardware data point: the maintainer's diagnostics from a MacBook Air (M2, 2022), 8 cores, macOS 27.2 (Build 26B5101f), reported the notch display as available, the power sensor as available (7.2 W at rest), the temperature sensor as available (48 C), a nominal thermal state and the Air default thresholds of 13 W and 19 W. This is one machine; other chips, the Pro family and other macOS versions remain untested. Upstream redistribution permission and App Store eligibility remain unresolved.

## 1.7.0 follow-up — October 13, 2026

Build 44 redesigns Settings into General, Glow and About (with a live power meter, plainer wording and the Glow mode selector with previews), adapts the glow to bright wallpapers with a Wallpaper setting, shows power as a continuous blue-to-yellow color ramp, draws the glow to follow the hardware notch, and turns the controls panel into an island that grows out of the notch. The island's black shell and the glow around it are drawn by the same Metal pass from one per-frame spring, so the glow follows the island; the controls window is fixed and transparent and its layers fade in; Reduce Motion fades without changing shape. The Glow modes were renamed (Auto, Off, Mid, High, Hot) and the panel and menu bar menu offer only Auto and Off. Performance and stability changes: temperature sensing skips keys the model does not have (about 4.8 ms to 1.7 ms per reading on the Air), the glow runs at up to 60 fps (120 Hz while the island moves) and 30 fps when steady, the Metal layer no longer waits on the main thread for a drawable, the controls draw their own shell if the renderer is unavailable, and the island is dismissed on display sleep.

The ZIP was built with `scripts/build-release.sh` and its extracted contents were inspected: version 1.7.0 / Build 44, arm64, SDK and minimum OS 27.0, strict signature validation and checksum. Signing is ad-hoc with hardened runtime; there is no Developer ID signature or notarization. The maintainer tested the packages on a MacBook Air (M2, 2022) running macOS 27.2 during development. Measured: sensor read time and the shader's GPU time (about 0.14 to 0.22 ms per frame) on that Mac. Not measured: whole-app CPU, GPU or energy use while running. Not independently verified: other chips, the Pro family and external or multiple displays; VoiceOver reading order and Full Keyboard Access focus order in the new panel and Settings; the selected Glow segment's appearance on the black island across appearance settings; and click-through behavior of the transparent controls window. Upstream redistribution permission and App Store eligibility remain unresolved.

## 1.7.1 follow-up — October 14, 2026

Build 45 is the 1.7.0 code, signed with a Developer ID Application certificate and notarized by Apple (ticket stapled). `scripts/notarize.sh` was validated first as a dry run on the 1.7.0 source (Apple's notary service returned Accepted; the stapled app passed `stapler validate` and `spctl --assess` as Notarized Developer ID), then run for this release. Each release package is verified by extracting the final ZIP into a new directory and checking its version, strict code signature, `stapler validate`, `spctl --assess` and checksum. Notarization removes the first-launch Gatekeeper warning; it does not change what was and was not verified about the app itself, which is unchanged from the 1.7.0 section. Upstream redistribution permission and Mac App Store eligibility remain unresolved.

## 1.7.2 release — October 14, 2026

Published as v1.7.2, signed with Developer ID and notarized (Apple: Accepted). The ZIP downloaded from GitHub was checked: checksum, version 1.7.2 / 46, strict code signature, hardened runtime, `stapler validate` and `spctl` (`accepted`, source `Notarized Developer ID`). New in this release: MIT `LICENSE` and credits, and a steadier island collapse (the glow window is no longer resized while the island moves). The collapse change was checked by building and running from Xcode on one MacBook Air (M2); frame rate and whole-app CPU, GPU or energy use were not measured. Other Mac models, external displays, VoiceOver and keyboard focus order remain unverified.

## 1.7.3 release — October 14, 2026

Published as v1.7.3, signed with Developer ID and notarized (Apple: Accepted). The ZIP downloaded from GitHub was checked: checksum, version 1.7.3 / 47, strict code signature, hardened runtime, `stapler validate` and `spctl` (`accepted`, source `Notarized Developer ID`). New in this release: the Settings window is built invisibly after launch, because the system's hang reports for 1.5.3 to 1.7.0 show 1.2 to 3.4 s on the main thread during the first open, and the island's content motion was reworked. Both were tried by the maintainer from Xcode on one MacBook Air (M2); Settings open time, animation frame rate and whole-app CPU, GPU or energy use were not measured. The hang reports also contain many WebKit frames although the app has no web view; their source is unknown. Other Mac models, external displays, VoiceOver and keyboard focus order remain unverified.

## 1.7.4 release — October 15, 2026

Published as v1.7.4, signed with Developer ID and notarized (Apple: Accepted). The ZIP downloaded from GitHub was checked: checksum, version 1.7.4 / 48, strict code signature, hardened runtime, `stapler validate` and `spctl` (`accepted`, source `Notarized Developer ID`). New in this release: the app icon and the menu bar icon. The compiled app icon was rendered and checked; the menu bar icon was checked as a drawing and from Xcode on one MacBook Air (M2). Other Mac models, external displays, VoiceOver and keyboard focus order remain unverified.

## 1.7.5 release — October 15, 2026

Published as v1.7.5, signed with Developer ID and notarized (Apple: Accepted). The ZIP downloaded from GitHub was checked: checksum, version 1.7.5 / 49, strict code signature, hardened runtime, `stapler validate` and `spctl` (`accepted`, source `Notarized Developer ID`). New in this release: the full-bleed app icon (the compiled icon was rendered and checked in its default appearance; Dark, Clear and Tinted are system-derived and were not reviewed by hand) and a hidden, default-off switch that lets the glow and the island be captured for documentation. The README screenshots were taken on one MacBook Air (M2) with that switch; the black notch in the glow images is drawn in because macOS screenshots omit it. Other Mac models, external displays, VoiceOver and keyboard focus order remain unverified.

## 1.7.6 beta — October 16, 2026

Published as the pre-release v1.7.6-beta (not the latest release; 1.7.5 remains the recommended download), signed with Developer ID and notarized (Apple: Accepted). The ZIP downloaded from GitHub was checked: checksum, version 1.7.6 / 50, `LSMinimumSystemVersion` 26.0, binary minimum OS 26.0, strict code signature, hardened runtime, `stapler validate` and `spctl` (`accepted`, source `Notarized Developer ID`). Build-level evidence for macOS 26: the compiler flagged one newer API (the segmented control's tabs role), now guarded; the shader library targets macOS 26; only standard system frameworks are linked. **Not verified: the app has not been run on macOS 26.** A tester with a notched MacBook on macOS 26 has been asked to try it and report with Copy Diagnostics.

## 1.8.0 beta — October 16, 2026

Published as the pre-release v1.8.0-beta (not the latest release; 1.7.5 remains the recommended download, and `appcast.xml` has no entry yet, so no one is offered this build by the updater). Assets: a DMG, a ZIP and `SHA256SUMS.txt`. Both packages were notarized (Apple: Accepted). The downloaded files were checked: checksums for both, the DMG's `stapler validate` and `spctl`, and, from the mounted DMG, version 1.8.0 / 51, `LSMinimumSystemVersion` 26.0, strict signature, `stapler validate` and `spctl` for the app, with Sparkle.framework embedded. Every nested component of the app has team 5F8A7ZD8D3 with the hardened runtime (checked on the 1.7.6 pipeline run). New: the DMG, Sparkle updates, the slower power readout, one hover haptic, the Settings activation fix, and release-script checks that can fail. **Not verified:** whether this build starts on macOS 26, the update flow (it needs a later release to update to), whether the Settings activation fix is complete (it was intermittent), and the feel of the haptic beyond the maintainer's trackpad.

## 1.8.0 release — October 16, 2026

Published as v1.8.0 (Build 52), signed with Developer ID and notarized for both the app and the disk image (Apple: Accepted). The assets downloaded from GitHub were checked: checksums for the DMG and the ZIP, `stapler validate` and `spctl` for the DMG, and, from the mounted DMG, version 1.8.0 / 52, `LSMinimumSystemVersion` 26.0, `SUPublicEDKey`, strict signature, `stapler validate` and `spctl` for the app. `appcast.xml` has the entry for build 52, and its EdDSA signature was verified against the downloaded DMG with Sparkle's `sign_update --verify` (the file length also matches). New since the 1.8.0 beta: the designed installer window, less explanatory text, and the fixes from the HIG review (Help menu, update-menu validation, no minimize button in Settings, Increase Contrast for the meter). **Not verified:** the update itself (the beta, build 51, is the only installed build that can be offered this one, and no one has run that update yet), how the app runs on macOS 26 (build-level checks only), VoiceOver and Full Keyboard Access, the fix for Settings sometimes opening behind other windows, and other chips, the Pro family and external displays.

### Automatic update verified — October 16, 2026

The maintainer updated the installed 1.8.0 beta (Build 51) to 1.8.0 (Build 52) with Check for Updates… on a MacBook Air (M2) running macOS 27.2, and it succeeded. This is the first end-to-end run of the update path: the appcast was fetched, the new version was offered, and the download was verified and installed. It covers one Mac, one macOS version and an update from the beta to the stable release; an update between two stable releases, the automatic daily check without a click, and updates on macOS 26 have not been run.
