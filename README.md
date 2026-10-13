# PeakGlow

A small macOS utility that shows system load as a soft glow around the MacBook notch. This fork builds on [lzt66666/notchpeakglow](https://github.com/lzt66666/notchpeakglow), with a native macOS interface, refined pointer interaction and English documentation. Development has been assisted by AI.

## Download

[Latest published release](https://github.com/aweekdayz/notchpeakglow/releases/latest).

Quit any running copy, extract the ZIP and move `PeakGlow.app` to Applications. Existing preferences are retained. The currently published 1.6.0 app is ad-hoc signed and **not Apple-notarized**. macOS may restrict its first launch; use Privacy & Security only if you trust the download.

The source audit changes described below are newer than the published 1.6.0 binary. See [Release audit](docs/Release-Audit.md) for validation and outstanding work.

## Requirements and compatibility

- macOS 27 or later.
- Apple Silicon MacBook with an available built-in notch display.
- Xcode with the macOS 27 SDK and Metal Toolchain for source builds.

| Device or configuration | Behavior | Validation status |
| --- | --- | --- |
| Notched MacBook Air, 13 or 15 inches | Air power presets; standard dynamic range when EDR headroom is unavailable | Family-level implementation; not every chip tested |
| Notched MacBook Pro, 14 or 16 inches | Pro power presets; display-dependent extended dynamic range | Family-level implementation; not every chip tested |
| External display connected, lid open | Glow stays on the built-in notch display, even when an external display is primary | Geometry handled in code; hardware verification pending |
| Closed-display mode or no notch display | No glow or hover target; open the app from Finder to access Settings | Safe fallback implemented; hardware verification pending |
| Intel Mac or desktop Mac | Outside the supported distribution target | Not supported |

Device detection uses product metadata and physical display size, rather than assuming a scaled resolution identifies a 16-inch display. Geometry follows the display's actual auxiliary top areas and backing scale. There is no claim of calibration for every M-series chip, core count or workload.

Initial full-glow / Boost presets are **13 / 19 W for Air** and **30 / 55 W for Pro or an unknown family**. These are adjustable starting points. Existing custom thresholds are not silently replaced. Use Settings → Power to apply the current presets or tune them to your workload.

## Use

PeakGlow runs without a Dock or menu bar icon. Hover over the notch for approximately 80 ms to open the controls; click the notch for immediate interaction. Move away, click outside or press Esc to close them. Menus and active mouse drags temporarily defer pointer dismissal.

| Glow mode | Effect |
| --- | --- |
| Auto | Follow measured system power; optional subtle glow at low load |
| Off | Turn the glow off |
| Soft | Preview the soft cyan, violet and pink glow |
| Boost | Preview the ice-blue glow with gentle breathing |
| Warm | Preview the steady warm temperature tint |

The controls expose one Settings button and a direct Quit button. In Auto, a connected game controller pauses the glow. Previews remain available. Reopening the application from Finder opens Settings.

Settings uses native SwiftUI forms, sliders, toggles and sidebar navigation. The Glow selector is a native AppKit segmented control hosted in SwiftUI, using the system tabs role. Buttons and the controls surface use system Liquid Glass. macOS decides how native materials appear under accessibility and appearance settings.

## How it works

`PowerSampler` reads the AppleSMC `PSTR` float sensor. A five-sample average, hysteresis and continuous dwell determine Low, Soft or Boost. Unsupported or failed readings display “Power data unavailable” and clear stale automatic load state. Failed driver connections retry at a bounded interval.

Metal draws outside the actual notch silhouette. A main-run-loop display link drives the animation; a transparent final frame is submitted before idle rendering stops. Display sleep or loss of the notch display stops the hidden renderer. EDR gain is limited by the display's current headroom; there is no requirement for HDR to use the app.

Temperature alerts combine a sustained high-temperature heuristic on recognized MacBook families with the system critical thermal state. Sensor keys vary by hardware. Missing samples clear the heuristic window and alert. A warm glow is a temperature indicator, **not confirmation of CPU throttling or a hardware safety system**.

## Build from source

You do not need to operate the Xcode application to use or build PeakGlow. The build still uses Xcode's compiler, SDK, asset compiler and Metal Toolchain. The checked-in project is sufficient; XcodeGen is optional when regenerating it from `project.yml`.

```sh
git clone https://github.com/aweekdayz/notchpeakglow.git
cd notchpeakglow
bash scripts/build-release.sh
```

If the Metal Toolchain is missing, install it using Xcode's Components settings or:

```sh
xcodebuild -downloadComponent MetalToolchain
```

The build script intentionally fails when required tools are absent. It does not silently substitute an old shader or icon. It compiles the layered `AppIcon.icon`, checks bundle metadata and required resources, signs the staged app and creates a ZIP and checksum in `build/release/`.

By default signing is ad-hoc. For a Developer ID build, set `PEAKGLOW_SIGN_IDENTITY` to an installed Developer ID Application identity. Apple notarization is a separate step and is not performed by this script. A Mac App Store submission needs its own signing, sandbox and API compatibility review.

`scripts/compile-preview-swift.sh` remains a **Swift executable-only fallback**. It validates SDK metadata but does not compile Metal, compile the layered icon, produce a complete application or perform notarization. The original 1.6.0 distribution used that fallback with previously compiled resources.

## Limitations

- AppleSMC sensor keys and the driver protocol are not a documented public power-measurement API. Availability is not guaranteed on every model or future macOS version.
- The SMC reading is not the same as a wall-outlet power meter and can be affected by charging and hardware behavior.
- Capture exclusion is requested using AppKit; invisibility in all screenshots or recording tools is not guaranteed.
- Reduced Motion is respected. Native system menus and security dialogs follow the system language; PeakGlow's own interface, logs and documentation are English.
- No automated interactive UI tests or cross-model hardware benchmarks have been performed.

## Attribution and licensing status

Original project: [lzt66666/notchpeakglow](https://github.com/lzt66666/notchpeakglow). The original project credits [exelban/stats](https://github.com/exelban/stats) as a reference for SMC access.

At the October 12, 2026 audit, the upstream repository had no license file and GitHub reported no detected license. This fork does not add a license or claim ownership of upstream code. Permission and any third-party obligations must be resolved before treating the project as cleared for redistribution or App Store submission.

See [Development notes](docs/Development.md), [HIG review](docs/HIG-Review.md) and [HIG reading log](docs/HIG-Reading-Log.md).
