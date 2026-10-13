# PeakGlow development notes

This document describes the current implementation. Earlier CPU-based and fullscreen-polling design notes are preserved in Git history, but are no longer the specification.

## Ownership and dependencies

This version is maintained by aweekdayz with AI-assisted development. See [Credits](../CREDITS.md) for provenance. It uses Swift, SwiftUI, AppKit, Metal, IOKit, GameController and ServiceManagement without third-party package dependencies. Upstream redistribution rights and the provenance of SMC-related code remain unresolved; see Credits.

## Runtime architecture

| Module | Responsibility |
| --- | --- |
| AppDelegate | Sampling callbacks, preferences, lifecycle, application menus and preview precedence |
| MachineProfile | Cached device metadata and adjustable family-level defaults |
| NotchedScreenFinder | Built-in display selection and positive notch geometry |
| PowerSampler | Bounded-retry AppleSMC connection, metadata cache and PSTR float decoding |
| LoadLevelStateMachine | Watt thresholds, hysteresis and continuous transition dwell |
| OverheatDetector / ThermalSMC | Temperature plateau heuristic, system critical fallback and validated sensor reads |
| GlowWindow / GlowMetalView | Transparent pass-through panel, display scale, EDR headroom and display-link lifecycle |
| GlowRenderer / Shaders.metal | Cached appearance snapshot, interpolated uniforms and transparent final frame |
| NotchHoverController | Dwell, notch hit target, outside-pointer polling, menu/drag grace and dismissal |
| BubblePanelController | Fixed-size native host and interruptible window translation/fade |
| BubbleContentView | English status, power reading, native Glow selector, Settings and Quit |
| SettingsView | Native grouped forms, sidebar, numeric entry, Reset and launch-at-login status |
| AppSettings / AppState | User preferences and scoped observable presentation state |
| FirstRunWindow | Initial guidance for a background application |

`CPUSampler` is retained as a legacy utility but is not started and does not contribute to load classification.

## Display and hardware boundaries

The application supports arm64 and macOS 27+. Geometry is derived from the built-in display, not the main display. There is no external-display glow fallback. When the notch display is unavailable, rendering stops and the hover panel and controls are dismissed. Finder reopening still provides access to Settings.

Air and Pro presets are family defaults, not a watt-per-core model or an independently measured calibration for each chip. The profile uses product metadata; a recognized Pro can use physical display width to distinguish 14 from 16 inches without relying on a user-selected scaled resolution. Unrecognized products remain unknown instead of being assumed to be a Pro.

Thermal heuristics use known family boundaries, not the unused per-model threshold fields from the old implementation. Unknown families use only the system critical thermal state. Missing sensor data resets continuous thermal dwell. Driver responses must succeed and provide the expected float type and length.

## Interaction invariants

- Keep the user-approved native NSSegmentedControl: selectOne, tabs role, automatic style, capsule border, equal segment widths.
- Keep the controls panel at 328 × 258 points; animate origin and opacity, not content dimensions.
- Establish the requested key appearance before revealing the nonactivating panel.
- Keep the hosting view transparent and rounded; preserve focus indicators on individual native controls.
- Pointer departure still dismisses after clicking controls, except while a menu or mouse drag is active.
- Keep Reset at the upper right with stable toolbar item identities.
- Numeric fields have no duplicate visual title; accessibility labels remain explicit.
- Do not replace system sliders with drawn controls or add meaningless tick marks.
- Preserve existing custom preferences when updating the application.

## Rendering and performance

Sampling, settings and presentation run on the main run loop. Power changes update the measurement subtree only while controls are visible. Rendering settings are captured when waking rather than rereading preferences each frame. The GPU submission gate permits two in-flight command buffers; this does not guarantee that every drawable request is nonblocking.

A completed fade commits a transparent frame before invalidating the display link. Display sleep and loss of the notch display stop the link immediately. Repositioning updates drawable size, notch coordinates and EDR headroom. No measured CPU, GPU or energy improvement is claimed without benchmarks.

## Build and distribution

Use `bash scripts/build-release.sh` for the full Xcode build, resource validation and packaging. The script uses the checked-in project and stages outside file-provider directories before signing. This avoids Finder metadata contamination during signing.

The `.icon` source must be processed by Apple's asset compiler; copying it into a hand-built bundle does not provide the compiled layered icon. The `.metal` source must become `default.metallib`. A Swift-only binary is not a complete substitute for those resource build steps.

The project explicitly targets arm64, uses hardened runtime and declares English as its development language. Code-signing identities are supplied at packaging time. Ad-hoc signing, Developer ID signing, notarization and Mac App Store signing are distinct distribution stages.

## Verification boundaries

Static review and direct optimized Swift compilation are available in the current environment. The installed Metal compiler and linker have compiled the current shader successfully. Component discovery in the restricted runner misleadingly reports it as missing; an explicit `PEAKGLOW_METAL_TOOLCHAIN` path avoids that lookup. The restricted pipeline failed at layered-icon export, but the same source built and packaged successfully in the user's normal terminal. Independent inspection of the 1.6.1 ZIP verified freshly compiled shader and icon resources, bundle/SDK metadata, checksum and strict signature validation. No application was launched for interactive testing. Hardware coverage is an implementation claim only until verified on the relevant MacBooks and display configurations.

## Maintainer identity update — Build 39

The project and bundle use `com.aweekdayz.peakglow`. Recognized preferences are imported once from the previous namespace; existing values in the new namespace win. The old identifier is retained only for compatibility. Automatic launch registration is managed by macOS and may need reenabling. Original credits are bundled as Credits.rtf and displayed in the native About panel; this changes maintenance branding without rewriting source authorship.
