# Release audit — October 12, 2026

Source revision: 1.6.1, Build 38 (unreleased). Current public binary: 1.6.0, Build 37.

## Checks completed

All application Swift and Metal source files, bundle metadata, Xcode project, project-generation configuration, shell scripts, current README, development notes and HIG history were reviewed. The user-approved Glow appearance and native selector were preserved.

| Area | Finding and action |
| --- | --- |
| Language | UI strings were English, but diagnostic logs, comments and README were not. All current tracked text is now English. Error messages no longer interpolate potentially localized system descriptions. Native system menus/dialogs follow macOS language. |
| Build consistency | Project and generator now agree on version 1.6.1, Build 38, macOS 27, arm64 and hardened runtime. English is explicit in the bundle and target. |
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
- A full Release Xcode build was attempted and failed at Metal compilation: the Metal Toolchain is missing.
- `xcodebuild -downloadComponent MetalToolchain` was attempted and failed fetching its component catalog in the restricted execution environment. This did not install the component.
- No application was launched for interactive testing, and no physical-device matrix or energy benchmark was performed.

The previous 1.6.0 package signature and checksum were verified during publication. Those checks do not verify a 1.6.1 package, which does not yet exist.

## Hardware coverage

The implementation accommodates notched Air and Pro families, Retina scale, variable notch geometry, non-primary built-in displays and dynamic EDR headroom. This is not evidence that every M-series chip works. PSTR and Tp* sensor availability can differ between devices and operating systems.

Pending user hardware checks: 13/15-inch Air; 14/16-inch Pro; scaled resolutions; external primary display with the lid open; disconnect/reconnect and closed-display mode; screen sleep/wake; full-screen Spaces and Stage Manager; appearance and accessibility settings; sensor-unavailable behavior. The application only draws on the built-in notch display. Intel and desktop Macs are outside the arm64 notched-MacBook target.

Power presets remain 13/19 W for Air and 30/55 W for Pro/unknown. They are adjustable family defaults, not per-chip performance normalization. Temperature alerts are heuristics, not proof of throttling.

## Remaining release requirements

1. Install the Metal Toolchain, then run `bash scripts/build-release.sh` for a complete source-to-package build, including the layered icon.
2. Have the user assess the new application without claiming automated UI coverage.
3. Confirm permission to redistribute upstream code and any relevant third-party obligations. Do not add a license on the upstream author's behalf.
4. For normal direct public distribution, supply a Developer ID identity and complete Apple notarization. Current ad-hoc signing does not provide either.
5. For the Mac App Store, separately investigate the AppleSMC protocol, sandbox compatibility, signing and review requirements. The current unsandboxed configuration is not App Store-ready.

Xcode's interface is optional for routine command-line builds. Its installed compiler, SDK, Metal and asset tools are required; the Swift-only preview build omits resource compilation and cannot certify a full release.
