# Release audit — October 12, 2026

Historical audit of 1.6.1 / Build 38 (never published separately; its changes shipped in 1.6.2). **Current public release: 1.6.5 / Build 42** — see the follow-up sections below, which supersede earlier status lines.

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
| Attribution | Identify the original project and its SMC reference. No upstream license file was found; GitHub reports `license: null`. No redistribution clearance is claimed. |

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
3. Confirm permission to redistribute upstream code and any relevant third-party obligations. Do not add a license on the upstream author's behalf.
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
