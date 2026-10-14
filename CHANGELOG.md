# Changelog

## 1.7.0 — Build 44 (not yet published)

- Redesign Settings into three pages with plainer wording. **General**: open at login, menu bar icon, hover delay, temperature warning. **Glow**: a live power meter that uses the glow's own colors, the two power thresholds ("Brighter glow from", "Strongest glow from") with a recommended-for-this-Mac button, the look (idle glow, size, brightness), and a collapsed Fine-tuning group holding the technical sliders with a short explanation each. **About**: this Mac, Copy Diagnostics, version, credits and a link to the source. Reset stays in the toolbar.
- The controls panel is now an island that grows out of the notch. The fixed transparent window is flush with the top of the screen and only a black shape inside it moves: it springs from the notch's own size and shape to the full panel (lower corners rounding out, top merged with the screen edge), the content layers settle in turn once the shell has opened, and it contracts back into the notch when it closes. Reversing mid-motion keeps the current velocity. With Reduce Motion on, the island fades in and out without changing shape. The panel is black with the dark appearance instead of Liquid Glass, and clicking the island's top area no longer closes it (the notch is covered while it is open); moving away, Esc and clicking outside still do.
- The glow adapts to bright wallpapers. A deeper, more saturated version of the same color ramp (deep blue, azure, green, olive, gold) with a slightly higher opacity keeps its contrast on light backgrounds, where the previous colors, yellow especially, nearly disappeared. Settings → Glow → Look → Wallpaper chooses Automatic (follows the system appearance), Light or Dark, and the glow cross-fades when it changes. Copy Diagnostics reports the setting.
- The power display is a read-only meter with no thumb: the whole color scale stays visible at low brightness, the part up to the current power is lit, and ticks mark the two thresholds. It updates only while Settings is open.
- Verified by a full Xcode build only; the layout has not been viewed on a Mac.

## 1.6.6 — Build 43 (not yet published)

- Add Copy Diagnostics to Settings → Appearance. It copies the Mac model, chip, macOS version, notch display, power and temperature sensor status, thermal state and key settings as plain text for bug reports, with no serial number or personal data. The bug report template and README troubleshooting section point to it.
- Verified by a full Xcode build; the report text has not been reviewed on other Mac models.

## 1.6.5 — October 13, 2026 (Build 42)

- Redraw the glow to follow the hardware notch: the shape merges with the top screen edge and only the lower corners are rounded, instead of a four-cornered pill. A thin lit edge now sits inside a tighter bloom and a faint tail for a clearer, more defined edge. Modes and settings are unchanged.
- Show power continuously: the glow's color moves along a single-direction ramp (blue, cyan, green, yellow) while brightness and bloom width grow with power over a wide range, mapped around the two Power thresholds and smoothed. Soft and Boost previews use fixed positions on the ramp. The orange and red temperature tint is unchanged and reserved for the warning.
- Verified by rendering the shader offscreen to still images and by a full Xcode build; the maintainer has not yet viewed it on a Mac.

## 1.6.4 — October 13, 2026 (Build 41)

- Add a menu bar icon so the main controls are reachable without the pointer. It can be turned off in Settings → Behavior → Menu bar.
- Remove the Show PeakGlow Controls command and its ⌥⌘P shortcut. The menu bar icon now shows system power, offers the Glow modes (Auto, Off, Soft, Boost, Warm) with a checkmark on the current one, and keeps Settings and Quit.
- Settings → Behavior lists Startup, Alerts, Menu bar, Interaction in that order.
- Use system text styles in the controls panel. The power readout is 26 pt (`largeTitle`) instead of a fixed 30 pt.

## 1.6.3 — October 13, 2026 (Build 40)

- Break the temperature-plateau window and the load-transition dwell when samples are interrupted (for example by system sleep), so a plateau or transition must be observed continuously after waking.
- Clamp the stored sampling interval (0.2–3 s) and frame rate (15–60 fps) to their Settings ranges.
- Build in the Swift 6 language mode: main-thread types are annotated `@MainActor` and run-loop callbacks assert main-actor isolation. Replace a deprecated `String(cString:)` use.
- Complete the menu bar: Hide Others, Show All, Minimize (⌘M), Zoom, and a shortcut (⌥⌘P) for Show PeakGlow Controls. These work only while PeakGlow is active; no global shortcut is registered.
- Show the menu bar while Settings is open: the app switches to a regular activation policy (menu bar and Dock icon) with the Settings window and returns to accessory mode when it closes. Previously the menus existed but could never be displayed.
- Verified: full Xcode release build through `scripts/build-release.sh` (ad-hoc, hardened runtime, not notarized), extracted-package inspection and a Swift 6 type-check without warnings. The maintainer tested the package on a Mac; there are no automated interactive tests or multi-model hardware results.

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
