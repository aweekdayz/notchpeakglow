# PeakGlow HIG review

Reviewed: October 11, 2026. Baseline: preview Build 10.

## Scope and evidence

The HIG spans six groups: Getting started, Foundations, Patterns, Components, Inputs, and Technologies. This review maps those groups to this macOS notch utility. It covers the relevant guidance retrieved from Apple's current HIG and inspects production source; it is not a claim to have read every cross-platform or technology-specific article. Some documentation pages return a JavaScript shell through direct retrieval; indexed Apple text supplied the accessible guidance. No application was launched or interactively tested for this review, at the user's request.

Apple recommendations and PeakGlow implementation proposals are distinct below. Items marked as gaps are source observations or design judgments, not measured runtime failures. The prior linked-SDK correction is implementation evidence, not a HIG certification.

## Coverage

| HIG group | Applicable topics | Source-level assessment |
| --- | --- | --- |
| Getting started | Design principles; Designing for macOS | Native controls now fit the platform. Command access and discoverability need work. |
| Foundations | Accessibility, layout, materials, motion, color, Dark Mode, typography, writing, branding, app icons | Semantic UI colors and system typography are present. Reduce Motion is supported. Fixed content sizes, small icon actions, and accessibility entry points need review. Native icon export remains incomplete in the preview workflow. |
| Patterns | Settings, onboarding, feedback, help, modality | Grouped settings and reset confirmation exist. Advanced settings lack explanations; unavailable/stale power readings and gamepad pause are not communicated. |
| Components | Buttons, sliders, toggles, segmented controls, labels, menus, toolbars, sidebars, split views, popovers, alerts | System controls are used without glass capsules. Precise settings currently require dragging. Hover dismissal does not account for keyboard focus. |
| Inputs | Keyboards, pointing devices, gestures | Notch hover/click and Esc exist. Full Keyboard Access has no discoverable entry to the panel. Standard Settings and Quit commands are incomplete. |
| Technologies | Platform appearance and accessibility integration | Correct SDK metadata enables new system styles; keep the build guard. Unrelated technologies such as payments, collaboration, spatial input, and widgets are outside this product's current scope. |

## Prioritized work

### 1. Give people reliable command access

Apple supports keyboard-only operation and conventional shortcuts, including Command-Comma for Settings. PeakGlow is an accessory app with no main menu installation in `main.swift` or `AppDelegate.swift`; Settings is reached through the panel or Finder reopening. Add a standard application menu when its windows are active, including Settings…, Quit, and Close where appropriate. Add an accessible way to open the panel that preserves the product's quiet, background-only intent. Do not introduce a global shortcut without a deliberate user-facing choice.

Sources: [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards/), [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus).

### 2. Separate hover preview from deliberate interaction

The custom panel closes 180 ms after the pointer leaves its region. `checkOutside()` protects held mouse buttons and tracked menus, but not keyboard focus. A clicked/key panel should remain available during keyboard interaction and dismiss on an explicit action or outside click. Keep fast, nonactivating hover access. This is a PeakGlow proposal informed by keyboard and transient-view guidance, not an Apple-mandated dwell time.

Sources: [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers/), [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards/).

### 3. Communicate actual state

`AppDelegate` ignores failed power reads, leaving the previous reading cached. Gamepad pause lives in `GlowWindow` and is not exposed to the panel. Distinguish current readings from unavailable/stale readings and explain when Auto glow is paused. Preserve the distinction between preview and real temperature alerts. A dash alone does not explain why data is missing. Use quiet inline feedback rather than frequent modal alerts.

Sources: [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback?changes=_9), [Writing](https://developer.apple.com/design/human-interface-guidelines/writing?changes=_1), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts).

### 4. Make precise settings easy

HIG suggests text fields or steppers alongside sliders when precision matters. Watt thresholds, timing, and frame-rate settings currently offer only continuous sliders and rounded display values. Add native numeric entry or appropriate discrete steps, with shared range validation. Retain continuous controls for visual adjustment where they are useful. Explain hysteresis, transition delay, sampling interval, and HDR gain; do not expose these terms as self-explanatory.

Sources: [Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders?changes=l_8_2), [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help?changes=_7).

### 5. Preserve accessibility and adaptable layout

The panel uses a fixed 328 × 258 frame; onboarding uses 420 × 340. Settings uses a fixed ideal sidebar width and a substantial minimum window width. Inspect wrapping, longer status text, display changes, and label/value accessibility before adding more content. The gear and More actions need deliberate usable target areas. Native materials should retain system contrast/transparency behavior. Custom Metal glow needs separate consideration; an accessibility preference does not automatically alter shader output. Avoid using color as the only status channel.

Sources: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility?changes=latest_maj_6_3&language=objc), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Color](https://developer.apple.com/design/human-interface-guidelines/color?changes=_5_2), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials).

### 6. Use system motion and material with restraint

Keep system Slider, Toggle, Picker, sidebar, toolbar, and glass button behavior. Do not add glass behind every row or draw a replacement thumb. Keep the custom glow as the distinctive content and the panel as its control surface. Reduce Motion branches already exist in the renderer, panel transition, and power-number animation. Do not replace native sidebar animation with additional competing animations. Frame pacing remains a user-observed issue; source inspection alone cannot establish smoothness.

Sources: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion?changes=l_9_3), [Branding](https://developer.apple.com/design/human-interface-guidelines/branding).

## Delivery boundary

This review changes no application behavior and creates no new app build. Build 10 remains the current preview. The user owns interactive testing; implementation work should include compilation and packaging, with explicit disclosure of unverified interaction behavior.
