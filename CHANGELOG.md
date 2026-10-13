# Changelog

## Unreleased

- Break the temperature-plateau window and the load-transition dwell when samples are interrupted (for example by system sleep), so a plateau or transition must be observed continuously after waking.
- Clamp the stored sampling interval (0.2–3 s) and frame rate (15–60 fps) to their Settings ranges.
- Build in the Swift 6 language mode: main-thread types are annotated `@MainActor` and run-loop callbacks assert main-actor isolation. Replace a deprecated `String(cString:)` use.
- Verified by a full Xcode Release build (unsigned) and a Swift 6 type-check without warnings; not tested on hardware or exercised interactively.

## 1.6.2 — October 13, 2026 (Build 39)

- Identify aweekdayz as the maintainer in project presentation and bundle metadata.
- Use the maintainer's application identifier and import recognized legacy preferences without overwriting new settings.
- Add a native About panel with bundled Credits and retain original project attribution in CREDITS.md.
- Preserve the approved glow and interface. Recheck launch-at-login registration after replacing an older app.
- Keep Git provenance and unresolved redistribution/licensing status explicit.
- Full Xcode package verified with the new bundle identity, compiled shader/icon/Credits resources, strict ad-hoc hardened-runtime signature and SHA-256 checksum. Published as the latest GitHub release.


## 1.6.1 — Build 38 (not published separately; included in 1.6.2)

- English interface, diagnostic logs, source comments and current documentation.
- Explicit arm64 build target, English bundle language and hardened runtime.
- Full Xcode resource-build and packaging script with SDK, shader, layered-icon, signature and checksum validation.
- Built-in notch selection with positive geometry checks; no glow on external displays.
- Physical-size Pro detection independent of scaled resolution; unknown models retain a generic fallback.
- Stop rendering when the notch display disappears or sleeps; refresh EDR headroom after repositioning.
- Dismiss controls when display geometry changes or the notch display disconnects.
- Bounded SMC reconnection attempts, validated thermal response metadata and cached temperature-key metadata.
- Clear stale automatic load and temperature alerts when readings become unavailable; accept a valid zero-watt reading.
- Clear persisted temperature alerts at startup and provide an accessible Settings fallback without a notch display.
- Match the alert-brightness control to the shader's actual 0.5–2× multiplier range.
- Document family presets, unverified hardware coverage, current build limitations and unresolved upstream licensing.

A complete Xcode source/resource build and local package succeeded on October 12, 2026. The 1.6.1 archive contains newly compiled shader and layered-icon resources; version, architecture, SDK, checksum and ad-hoc hardened-runtime signature checks passed. The package is not notarized and was not released on its own.

## 1.6.0 — 2026-10-12

- Native macOS 27 Liquid Glass controls and English Settings.
- Soft low-load glow, ice-blue Boost and warm temperature alerts.
- Native Glow selector with Auto, Off, Soft, Boost and Warm previews.
- Refined notch hover presentation, consistent focused appearance and automatic pointer dismissal.
- Direct Quit button and a single Settings entry in the controls panel.
- Improved Settings grouping, explanatory text and numeric-field layout.
- Reduced power-sampling and rendering overhead; transparent final fade-out frames.
- Requires macOS 27 or later and Apple Silicon. Build 37.

Distribution uses ad-hoc signing and is not Apple-notarized.
