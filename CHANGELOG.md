# Changelog

## Unreleased

Battery and charging, and a lighter glow.

**Battery**
- A Battery page in Settings: the charge and what it is doing, the time until full or empty, the battery's maximum capacity and its capacity in mAh, the cycle count, the power adapter, the charging or battery power, the current and the voltage, and the battery temperature when the Mac reports one (this Mac's macOS does not). The values come from the system's `AppleSmartBattery` entry; plugging in and out arrive as system notifications, and the details are read every two seconds only while the controls or Settings are showing them (otherwise once a minute). The Diagnostics include a battery line without any serial number.
- The controls panel shows four things about the battery, nothing else: the charge and the system power as two large readings (42 pt, scaling with the large title style), the estimated time or the state under the charge ("1 h 15 min until full", "6 h 50 min remaining", "Charging", "Not charging" when a charger is connected but the battery is not taking charge, "Fully charged"), the adapter ("Adapter 100 W") and the power on one line below. While charging the power is the charging power from the system's power telemetry ("Charging 35.7 W"); on battery the line has no power, because the system power beside it already is the discharge. The line keeps its room, so connecting a charger fades it in without moving anything, and the charge is green for as long as the battery is charging. There is no battery icon in the panel. The menu bar menu has a battery line.
- Charging is detected from three signals, not one: the registry's flag, the system's own power-source state and the direction of the current, and the monitor reads again 1, 3, 6 and 12 seconds after a charger is connected. Before, a Mac that was charging could read "Plugged in, not charging" for up to a minute. A Mac that is plugged in and holding its charge (for example at 80%) still reads "Plugged in, not charging".
- Every battery icon in the app (the island, the Battery page and the sidebar; the controls panel has none) is made of unchanged system symbols, sized by a text style, with the bolt scaled down (about 60%) so it sits on the battery like the system's: the system's battery for the level (red at 20% or less on battery), and while charging that battery in green with the system's `bolt.fill` on it. The system draws a bolt battery only when it is full, so the combination is what shows 61% while charging; at 100% the full battery has no bolt. The sidebar entry is a plain system symbol like the other three.

**Charging in the glow**
- While the Mac charges, a soft green light travels slowly along the notch over the power color, and the glow stays on at low load. With Reduce Motion the light is steady.
- Plugging in the charger (and reaching full charge) opens an island out of the notch, laid out like the iOS one: a black bar with "Charging" on the left and the charge in green with a battery on the right ("Charged" when full). It is exactly as tall as the notch, its content is centered on that height, and its width follows the notch. Nothing grows or bounces: the two sides start beside the notch, slide outward with the shell and fade in, and slide back and fade out as it closes, with springs that match the renderer's. It ignores the pointer, never takes focus, tells VoiceOver "Charging, 62 percent", fades only with Reduce Motion, gives way when the controls open, and its window is built ahead of time. When the controls are already open, or the island is off, a ripple is used instead.
- Fix: right after unplugging, the panel could show "until full" and "Charging" for a moment before switching to battery, because the registry's external-power flag lags; whether a charger is connected now comes from the power-source API the system's battery menu uses.
- Fix: the island could jump to the size of the controls panel just before it closed, because the glow window's layout (which runs when display parameters change, as plugging in a charger can cause) reset the island's shell size. The size is now set only when an island opens.
- Both can be turned off in Settings → Battery → Charging.

**Settings and the controls panel**
- Type uses only the system text styles in the default design (no fixed point sizes, no rounded design); the panel is 10 pt shorter for it.
- The live parts of Settings (the power card, the Battery page and the sidebar's battery icon) watch the readings themselves. Before, the whole window watched them and rebuilt its page on every reading; measured offscreen, one update cost up to 25 ms of main thread on the General page and now costs about 1.5 ms (13 ms to 2.6 ms on About).
- Battery page, Health: each measure is one row with a thin system progress bar; the cycle count bar is neutral gray.
- The power meter no longer fills while the panel opens, and its lit part is a clip instead of a mask; offscreen, that cut the panel's opening cost by about 40%, but that environment cannot tell whether a real display drops frames. A restyle of Settings toward System Settings was tried and taken back at the maintainer's request; the look is as it was and Check for Updates stays in About.

**Less work for the glow**
- The render loop used to redraw the glow about 30 times a second for as long as it was on, even when nothing moved (the default faint idle glow included). It now stops once every value has reached its target and nothing animates by itself, and starts again on a change. The power reading moves by a watt or so every half second at idle, which kept waking it, so the glow follows a small change only once it is about seven percent of the color ramp and at least 2.5 seconds after the last one (a big jump at once), at 20 frames per second; the charging light is drawn at 20 too. Measured on release builds on a MacBook Air (M2) on battery, Auto at idle, over 50-second windows, alternating the builds: the installed 1.8.0 used about 3.9 to 4.2% of one core, this build about 0.5%, and with the idle glow off both used about 0.35%, which is what the sensors and timers cost. A load check showed the glow still turning warm under load and returning, and the loop stopping again once it settled. GPU and whole-system energy were not measured.

**Not verified on a real screen:** the island's motion, the charging light, the new panel layout and the Battery page were rendered offscreen only, and charging was tested with synthetic readings because the charger was unplugged when the code was written.

## 1.8.0 — October 16, 2026 (Build 52)

The first stable release with automatic updates, the disk image and macOS 26 support. The automatic update from the 1.8.0 beta to this release has been run successfully on one Mac. It includes everything in the 1.8.0 beta below, plus:

- HIG review of the whole app (see `docs/HIG-Review.md`), with four fixes: a Help menu (PeakGlow Help and Report an Issue…); "Check for Updates…" is dimmed while a check is running; the Settings window no longer has a minimize button; and with Increase Contrast on, the power meter's unlit track and its threshold ticks are stronger. VoiceOver and Full Keyboard Access were not tested.
- A designed installer window. The disk image now opens to a slate background with the notch and its glow at the top, a large arrow from the app to the Applications folder and "Drag PeakGlow to Applications", with large icons. It is laid out by dmgbuild (`scripts/dmg`), so Finder's own scripting is not needed. The slate is a mid-tone on purpose: Finder draws the file names in black or white and cannot be told otherwise, so a mid-tone keeps them readable in light and dark appearance. Checked by opening the image in Finder; the pipeline ran end to end and Apple accepted it.
- Cut the app's explanatory text. Removed what repeats the control's own label or is obvious from it: the notes under the Menu bar section, the hover delay, glow size, base opacity, breathing rate, warning brightness and warning size sliders, the Updates note, the long Glow mode and Power now notes, the "System power" label beside the number (it now appears only when power data is unavailable), and the tooltips that repeated the Settings and Quit button labels. Shortened what remained: the Temperature, Wallpaper, sampling interval, frame rate, HDR and About notes. The first-run window no longer says the app has no menu bar icon, which has been untrue since the menu bar icon was added; it now says to hover over the notch and where Settings is, and the window is shorter. The Mid, High and Hot captions in Settings now say how to stop previewing.

## 1.8.0 beta — October 16, 2026 (Build 51)

- Fix Settings sometimes opening behind other windows and looking inactive (gray window buttons, no focus) even after clicking it. Right after the app switches from a background app to a regular one, the system may ignore the first request to activate it. Settings now asks, checks that the app is active and the window is key, and asks again a few times over the next second until it has worked. The cause is inferred from the symptom and the activation rules; it could not be reproduced here, so whether it is fully fixed needs checking over several openings.
- Automatic updates with Sparkle. The app checks for a new version about once a day, and "Check for Updates…" is in the menu bar menu, the app menu and Settings → About, together with a switch for the daily check. Updates come from a signed `appcast.xml`, and each is verified against an EdDSA key and the app's Developer ID signature before it replaces the app. Test releases are on a separate channel and are not offered to stable users. Builds and notarizes with Sparkle embedded and every component signed with the same identity; the update flow itself has not been exercised yet, because it needs a second release to update to. People on versions before this one must install it by hand once.
- Fix the release script's safety checks. They used `[[ ]]`, and under macOS's bash 3.2 a failing `[[ ]]` does not stop a `set -e` script, so none of them could fail (one still required the minimum system version to be 27.0 after it became 26.0, and passed anyway). They now use `[ ]`, the stale version check is corrected, and the script was run to confirm that every check passes on the current build.
- Release packaging: `scripts/notarize.sh` now also builds a disk image with the app beside an Applications shortcut, signed, notarized and stapled, so installing is one drag instead of moving the app by hand. The ZIP stays as an alternative. Run end to end; the mounted image was checked (contents, the app's signature, stapling and Gatekeeper).
- The power readout changes more slowly and steadily. It shows the mean of the last five samples (about two and a half seconds) and updates every one and a half seconds, instead of every half second with the raw sample. The meter, the dot color and the Settings meter follow the same value; the glow itself is unchanged. Opening the controls or Settings shows the current value at once.
- One haptic: a light tap on a Force Touch trackpad when the controls open as the pointer settles on the notch, with an on/off switch in Settings → General → Notch controls (on by default). Nothing else in the app taps, so the tap keeps its meaning. The tap uses the `generic` pattern, Apple's choice for an action no other pattern describes, picked by the maintainer in a blind comparison: `alignment` was too light to notice and `levelChange` is for discrete levels. It plays only while a finger is on the trackpad, and the system's trackpad setting applies.

## 1.7.6 beta — October 16, 2026 (Build 50)

- Support macOS 26. The deployment target and `LSMinimumSystemVersion` are now 26.0 (they were 27.0). Building with the macOS 27 SDK for a macOS 26 target, the compiler flagged one newer API, the Glow selector's tabs role, which is now used only on macOS 27 or later; on macOS 26 the selector is a plain segmented control. The binary's minimum OS is 26.0. Not verified: the app has not been run on macOS 26, so look, layout and behavior there are unchecked.

## 1.7.5 — October 15, 2026 (Build 49)

- The app icon now fills the whole icon instead of showing a screen inset with a thick dark border: the icon itself is the top of a screen, with the notch hanging from the top edge and its glow spreading well down the icon, and the system supplies the outer shape. The notch layer now uses the system's Liquid Glass treatment. The separate "screen" layer is removed. Checked by building and rendering the compiled icon (default appearance); the Dark, Clear and Tinted appearances are derived by the system and were not reviewed by hand. An attempt to give the Tinted appearance its own single-color glow was not accepted by the icon compiler and was dropped.
- Add a hidden switch for documentation images. The glow and the island ask the system to stay out of screenshots and recordings; `defaults write com.aweekdayz.peakglow allowScreenCapture -bool true` and a relaunch allows capture. It is off by default and has no control in the interface, so behavior for users is unchanged.

## 1.7.4 — October 15, 2026 (Build 48)

- New app icon and menu bar icon. The icon is a screen with the notch lit by the glow's own colors (blue, cyan, green, yellow), replacing the rainbow arc, and a leftover unused background image was removed from the icon bundle. The menu bar icon (also used in the island's header) is a drawn template image of a screen with a notch instead of the generic "waveform.path" symbol, so it follows light and dark menu bars. Checked by building and by rendering the compiled app icon; the menu bar icon was checked only as a drawing, not in the real menu bar.

## 1.7.3 — October 14, 2026 (Build 47)

- Settings no longer freezes the first time it is opened after launch. The system's hang reports from 1.5.3 to 1.7.0 show the main thread busy for 1.2 to 3.4 s inside the first `setContentView` (SwiftUI toolbar bridging, a window resize and a first full layout), with page-ins from disk on an 8 GB Mac. Settings is now built invisibly 2.5 s after launch, while nobody is waiting, and shown from that ready window. The cost moves to launch: the glow can stall for about a second or two once, shortly after start. If Settings is opened during that build it opens as soon as the build has settled, with a 10 s safety timeout. Checked by building; the open time itself was not measured.

- Rework how the island's content appears and leaves. Opening: each layer settles with a spring from slightly small (94%), blurred and 8 pt high, in turn from the top down, so the content follows the shell's bounce instead of fading in flat. Closing: the lowest layers leave first in about 0.1 s and the shell starts to contract 50 ms later, so the content never trails the shell. The Glow selector, a native control, keeps to opacity and offset. With Reduce Motion the layers only fade, as before. Checked by building; how it feels in motion has not been checked.

## 1.7.2 — October 14, 2026 (Build 46)

- Add an MIT `LICENSE` for this repository, listing the original author and the maintainer. The About window's credits now say the app is released under the MIT License and link to it, instead of saying redistribution permission needs confirmation. The upstream README declares MIT; the upstream repository has no license file, which is recorded in `CREDITS.md`.
- Make the island's collapse steadier. The glow window is no longer resized when the island opens or finishes contracting (a resize showed one stretched frame of the old drawable at the end of the collapse, and a late "island hidden" callback could shrink the window after a quick re-open); it always holds the island and its halo, so the glow drawable is larger at rest (about 1 M pixels instead of 0.4 M). Waking the renderer no longer resets the requested frame rate from 120 Hz to the normal rate, and the display link takes the new rate at once instead of on its next tick, so the first frames of the island's motion are not slow. Checked by building and by running from Xcode; frame rate and whole-app GPU or energy use were not measured.

## 1.7.1 — October 14, 2026 (Build 45)

- The release is signed with a Developer ID Application certificate and notarized by Apple, with the ticket stapled so it also passes Gatekeeper offline. Releases up to 1.7.0 were ad-hoc signed and not notarized. The code is identical to 1.7.0.
- `scripts/notarize.sh` ran end to end for the first time: build, Developer ID signature with a secure timestamp, notarization (accepted), staple, validation and `spctl` assessment (`accepted`, source `Notarized Developer ID`), then a new ZIP and checksum.

## 1.7.0 — October 13, 2026 (Build 44)

- Redesign Settings into three pages with plainer wording. **General**: open at login, menu bar icon, hover delay, temperature warning. **Glow**: a live power meter that uses the glow's own colors, the two power thresholds ("Brighter glow from", "Strongest glow from") with a recommended-for-this-Mac button, the look (idle glow, size, brightness), and a collapsed Fine-tuning group holding the technical sliders with a short explanation each. **About**: this Mac, Copy Diagnostics, version, credits and a link to the source. Reset stays in the toolbar.
- The controls panel is now an island that grows out of the notch, and the glow follows it. The island's black shell is drawn by the same Metal pass as the glow, from one spring computed per frame: it starts as the notch's own size and lower-corner radius, grows with its top merged into the screen edge, rounds to 24 pt, and the glow wraps its current outline throughout (the glow window grows to hold the island and shrinks back after it has contracted). The shell asks for up to 120 Hz while it moves. The controls window is fixed, transparent and flush with the top of the screen; its layers fade in once the shell has mostly opened and leave quickly. With Reduce Motion on, the island stays full size and only fades. Controls are laid out for it: the name and the live power sit in the band beside the notch, with the status, a power meter in the glow's colors (thresholds marked), the Glow selector, Settings and Quit below. The panel is black with the dark appearance instead of Liquid Glass, is excluded from screenshots like the glow, and clicking the island's top area no longer closes it (the notch is covered while it is open); moving away, Esc and clicking outside still do.
- Lower the steady-state cost. Temperature sensing remembers which sensor keys this model does not have instead of probing all 23 every second (about 4.8 ms to 1.7 ms per reading on a MacBook Air M2). The glow drops to 30 frames per second after about two seconds without a visible change and returns to the maximum frame rate at once when something changes. The maximum frame rate now defaults to 60 fps (it was 30), so motion is smoother while the glow changes. The temperature timer allows the system to coalesce its wake-ups. Measured: sensor reads and the shader's GPU time (about 0.14 to 0.22 ms per frame on the M2). Not measured: whole-app CPU, GPU or energy use while running.
- Make the Glow modes understandable. Soft, Boost and Warm were previews with unclear names; they are now **Mid**, **High** and **Hot** (Auto and Off are unchanged), the controls panel and the menu bar menu now offer only Auto and Off (the previews are for tuning colors and brightness, so they live in Settings → Glow beside those settings; while one is on, neither segment is selected and the panel says "Previewing. Choose Auto to stop"), the selector at the top of Settings → Glow has all five choices with a plain explanation of the current one, and Copy Diagnostics uses the new names.
- Lay the controls panel out around a large power reading: the name and a short status (with a dot in the glow's current color) sit beside the notch, the reading is 40 pt and scales with text size, and Settings is a labeled button next to Quit. The island is 384 pt wide and 220 pt tall below the notch.
- Stability fixes in the new rendering and island code: the Metal layer no longer waits up to a second for a free drawable on the main thread (it skips the frame); if the renderer is unavailable the controls draw their own black shell so they stay readable; the island is dismissed when the display sleeps instead of being left floating; the renderer refuses to start if the shader's parameter struct layout ever stops matching. The island's spring was checked numerically at 30, 60 and 120 Hz and with 0.1 s hitches (finite, settles, about 2.6% overshoot, reversal settles).
- The glow adapts to bright wallpapers. A deeper, more saturated version of the same color ramp (deep blue, azure, green, olive, gold) with a slightly higher opacity keeps its contrast on light backgrounds, where the previous colors, yellow especially, nearly disappeared. Settings → Glow → Look → Wallpaper chooses Automatic (follows the system appearance), Light or Dark, and the glow cross-fades when it changes. Copy Diagnostics reports the setting.
- The power display is a read-only meter with no thumb: the whole color scale stays visible at low brightness, the part up to the current power is lit, and ticks mark the two thresholds. The lit part follows the reading smoothly (a retargetable animation, so continuous readings do not jerk), a soft highlight marks its leading edge, and in the controls panel it fills up from empty as the island opens; with Reduce Motion on it is not animated. It updates only while Settings is open.
- Verified by a full Xcode build through `scripts/build-release.sh`, offscreen renders of the shader, the panel content and the power meter, numeric checks of the power mapping and the island spring, and sensor timing on a MacBook Air (M2, 2022). The maintainer tested the packages on that Mac while the changes were made. Not verified: other Mac models, multi-display setups, and the animations' timing and smoothness beyond that Mac.

## 1.6.6 — October 13, 2026 (Build 43)

- Add Copy Diagnostics to Settings → Appearance. It copies the Mac model, chip, macOS version, notch display, power and temperature sensor status, thermal state and key settings as plain text for bug reports, with no serial number or personal data. The bug report template and README troubleshooting section point to it.
- Verified by a full Xcode build and a maintainer test on a MacBook Air (M2, 2022) running macOS 27.2: the report showed the power and temperature sensors as available. It has not been reviewed on other Mac models.

## 1.6.5 — October 13, 2026 (Build 42)

- Redraw the glow to follow the hardware notch: the shape merges with the top screen edge and only the lower corners are rounded, instead of a four-cornered pill. A thin lit edge now sits inside a tighter bloom and a faint tail for a clearer, more defined edge. Modes and settings are unchanged.
- Show power continuously: the glow's color moves along a single-direction ramp (blue, cyan, green, yellow) while brightness and bloom width grow with power over a wide range, mapped around the two Power thresholds and smoothed. The Mid and High previews use fixed positions on the ramp. The orange and red temperature tint is unchanged and reserved for the warning.
- Verified by rendering the shader offscreen to still images and by a full Xcode build; the maintainer has not yet viewed it on a Mac.

## 1.6.4 — October 13, 2026 (Build 41)

- Add a menu bar icon so the main controls are reachable without the pointer. It can be turned off in Settings → Behavior → Menu bar.
- Remove the Show PeakGlow Controls command and its ⌥⌘P shortcut. The menu bar icon now shows system power, offers the Glow modes (Auto, Off, Mid, High, Hot) with a checkmark on the current one, and keeps Settings and Quit.
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
