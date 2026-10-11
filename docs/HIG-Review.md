# PeakGlow HIG review

Reviewed: October 11, 2026. Baseline: preview Build 10.

## Scope and evidence

The complete current HIG article reading is finished: Getting started 9/9, Foundations 18/18, Patterns 25/25, Components 64/64, Inputs 13/13 and Technologies 29/29, totaling 158 article bodies. The reading includes cross-platform considerations, technology-specific articles and the alternative content behind 162 tab options on 28 pages. Rendered official article bodies were read in the browser, rather than relying on search summaries. Article links were checked for omitted HIG pages and nested aliases; Spatial interactions redirects to Nearby interactions. Linked API documentation and embedded videos/audio are separate resources and were not fully reviewed. The per-article ledger is [HIG-Reading-Log.md](HIG-Reading-Log.md).

The implementation observations below come from the earlier Build 10 source review, combined with this complete guidance reading. No application was launched or interactively tested, at the user's request. The baseline observations below are retained for context; the Build 11 implementation is recorded at the end.

Apple recommendations and PeakGlow implementation proposals are distinct below. Items marked as gaps are source observations or design judgments, not measured runtime failures. The prior linked-SDK correction is implementation evidence, not a HIG certification.

## Product relevance after complete reading

All articles were read. This table selects the topics that materially affect this macOS utility; topics not listed here are still covered in the reading ledger.

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

Liquid Glass belongs primarily to navigation and controls, while content should retain its own hierarchy. Native SwiftUI is the default implementation choice; use system AppKit integrations where macOS window or panel behavior requires them. Native appearance alone is insufficient without the expected focus, activation, menu and dismissal behavior. Typography explicitly states that macOS does not support Dynamic Type; use Mac system text styles and adaptable layout rather than promising iOS-style automatic text scaling. A power reading is a measurement, not task completion, so a native Gauge is more semantically appropriate than a ProgressView if a range display is needed. The Activity rings design is reserved for activity goals and must not be repurposed for power.

Sources: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion?changes=l_9_3), [Branding](https://developer.apple.com/design/human-interface-guidelines/branding).

Additional sources: [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Gauges](https://developer.apple.com/design/human-interface-guidelines/gauges), [Activity rings](https://developer.apple.com/design/human-interface-guidelines/activity-rings), [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Windows](https://developer.apple.com/design/human-interface-guidelines/windows).

## Delivery boundary

Build 11 implements the following changes based on this review:

- Standard app, Edit, and Window menus, including Settings (Command-Comma), Quit (Command-Q), Close (Command-W), and Show PeakGlow Controls. These commands are available while PeakGlow is active; no global shortcut is registered.
- Hover opens a nonactivating preview. Clicking the notch/panel or using the Window command engages it for keyboard interaction; pointer departure then leaves it open. Escape, Close, and outside clicks dismiss it.
- Waiting and unavailable power states replace cached numeric readings with a dash and explanatory text. A failed read clears the averaging window and pending load transition. Opening the panel checks cached reading age. Auto mode explains game-controller pause.
- Native numeric TextFields and stepped native Sliders for load thresholds, hover delay, breathing rate, HDR/alert gain, frame rate, hysteresis, transition delay, and sampling interval. Numeric entry is range-clamped and uses the same underlying bindings as sliders. Advanced timing and HDR settings have inline explanations.
- Larger icon targets and explicit power accessibility labels; existing system materials and Reduce Motion behavior are retained. No custom replacement control or sidebar animation was added.

Compilation and linked-SDK metadata verification passed using the installed macOS SDK. A new preview package was produced. The app was not launched or interactively tested, as requested. Keyboard focus, control appearance, text wrapping, sidebar motion, and screen/Space transitions remain for user verification. Native icon export remains outside this build.


## Build 12 follow-up: slider semantics and stable panel layout

Apple's macOS slider guidance supports both marked and unmarked tracks. Tick marks should improve clarity and locating values; text fields can provide exact entry. Build 11 incorrectly coupled numeric-entry precision to the stepped Slider initializer, generating dense tick marks. Build 12 uses unmarked native SwiftUI Sliders and retains exact native numeric fields. Frame rate remains integer-valued without drawing a mark for every frame. No custom slider or thumb is introduced.

The panel now reserves separate measurement and two-line status regions, gives the native More menu a stable footprint, and aligns content from the top. Cached measurement refresh disables first-presentation number animation. The hosting view follows its panel bounds. Entrance/exit animate opacity at the anchored final position rather than moving the panel. These address source-level causes of perceived layout shifts; they are not a runtime confirmation that the reported stutter is resolved.

Build 12 Swift compilation and SDK metadata verification passed. The user retains interactive verification; no application was launched.


## Build 13 follow-up: publication and presentation ordering

The user reports that the layout stutter persists in Build 12. Fixed layout space alone did not resolve the report. Source review found that streaming power and availability were separate AppState publications observed by the entire panel, including native controls. They now publish one equatable reading snapshot through a dedicated PowerReadingState, observed by the measurement subtree. Hidden sampling still avoids publishing to the view.

A newly shown panel is attached to its window at zero opacity before final layout. A generation-guarded main-queue update and the first display-link tick prepare the attached hosting hierarchy before the fade advances. Dismissal invalidates queued preparation, preserving rapid reopen/reversal behavior. Reduce Motion skips the fade after layout. This removes an immediate-show-before-layout path; the cause of the user's visible stutter remains unconfirmed without runtime observation.

Build 13 compiled successfully and retained the checked linked SDK metadata. Packaging signature verification passed. No application was launched or interactively tested.


## Build 14 follow-up: selection typography and settings clarity

The user confirms Build 13 resolved the panel layout stutter. Keep its measurement isolation and presentation sequencing. The user reports that the initially selected Appearance sidebar row retains bold text after navigating away. Build 14 uses stable CaseIterable page identities and explicitly derives label font weight from current selection (semibold selected, regular otherwise), retaining the native sidebar selection, focus and background. The typography report remains for user verification; no runtime reproduction was attempted.

Advanced settings now group related controls under Rendering, Temperature alerts, and Load response. Unmarked native sliders expose current values through system help; numeric fields show their accepted ranges through help. Behavior explains hover/click/Escape and game-controller pause. Launch at login distinguishes enabled, requested-but-awaiting-approval, and disabled states; pending approval has a native action that opens System Settings Login Items. Returning to the app refreshes system status. These implement settings grouping, contextual help, feedback and selection guidance without replacing system controls.

Build 14 compiled with the installed SDK and passed linked-SDK metadata validation and package signature verification. The app was not launched or interactively tested, at the user's request.


## Build 15 follow-up: toolbar grouping

The user supplied a cropped titlebar screenshot showing Power at the leading edge, with the sidebar toggle and icon-only Reset grouped near the middle and substantial unused trailing space. Build 15 adds the macOS 26 native flexible ToolbarSpacer before the primary action and explicitly uses title-and-icon labeling for Reset. Native sidebar navigation, toolbar backgrounds and glass rendering remain system-managed. Older macOS retains its existing toolbar spacing.

Swift compilation, SDK metadata guard, diff whitespace check and preview signature verification passed. No app was launched or interactively tested; the resulting toolbar placement remains for user confirmation.


## Build 16 follow-up: initial sidebar selection colors

The user reports the initially selected Appearance row starts with black text, while subsequent selections use white. Build 16 replaces plain selectable Label rows with value-based native NavigationLink rows inside the existing selection-bound sidebar List. The system owns selected foreground and background colors; selection-derived weight is retained. Settings activates the accessory app before constructing/showing the window, rather than after ordering it front, addressing initial active/inactive rendering differences. Neither source change establishes the runtime cause or resolution without observation.

Build 16 compiled and passed SDK metadata and package signature validation. No application was launched or interactively tested. First-open selected color, keyboard navigation, and inactive-window selection appearance remain for user confirmation.


## Build 17 follow-up: selection versus keyboard focus

The user confirms Build 16 did not resolve the first-open black-text report. Source inspection shows an initial List selection but no initial sidebar focus declaration. Build 17 binds the native List to FocusState and supplies defaultFocus at the split-view root with automatic priority. This initializes focus while leaving user-directed navigation to the system. All manual sidebar font-weight overrides are removed; NavigationLink and Label use the system's typography and selection colors. Selection and keyboard focus are distinct; focus is a candidate cause, not a runtime diagnosis.

Primary API reference: [defaultFocus](https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:)), [FocusState](https://developer.apple.com/documentation/swiftui/focusstate/). Build 17 compiled successfully, passed linked SDK metadata and signature verification, and was packaged without launching the application. First-open selection color and keyboard focus remain for user verification.


## Build 18 follow-up: mounted selection and leading navigation

The user reports Build 17 still has initial selected-text inconsistency and supplies a crop identifying the sidebar toggle as too far right. Build 18 removes the automatically positioned sidebar toolbar item and supplies a native SwiftUI Button in navigation placement, bound to NavigationSplitView column visibility. Reset remains a separate trailing primary action with native flexible spacing.

Initial selection now starts nil and is set to Appearance once through the mounted view task, with initial sidebar focus requested at the same point. A newly created Settings window stays transparent until that update and its following layout pass finish, avoiding exposure of the unselected intermediate frame. Subsequent Settings openings preserve page/focus state. The native Label/NavigationLink controls retain system font and color ownership. This targets initial selection publication rather than hardcoding a selected foreground or cycling selection after presentation. The runtime cause remains unconfirmed; the user owns interactive verification.

Build 18 compiled and passed linked SDK metadata, diff whitespace and signature validation. No app was launched or interactively tested. Verify first-open selection color, toolbar navigation placement and sidebar collapse/expand.


## Build 19 follow-up: sidebar toolbar ownership

The user confirms Build 18 resolves Appearance's initial selection issue; preserve its initialization path. The user explicitly requests that Reset not move, while the sidebar toggle remains too far right. Build 19 declares the expanded sidebar's native navigation toolbar item on the sidebar List instead of the split-view root. When the sidebar is hidden, the same native action is supplied at the root so reopening remains accessible. Conditions are mutually exclusive. Reset placement, flexible spacing and labeling are unchanged.

Compilation, SDK metadata, diff whitespace and packaging signature verification passed. No app was launched; expanded/collapsed toggle position remains for user verification.


## Build 20 follow-up: observed duplicate sidebar toggles and Reset restoration

The user clarifies that Reset should return to its earlier placement and explicitly asks the agent to inspect the sidebar toggle position. Read-only observation of the Downloads preview Settings window found two toolbar sidebar buttons: the custom leading Toggle Sidebar and a residual automatic Hide Sidebar nearer the middle. The earlier root-only toolbar removal did not remove the column-scoped default item.

Build 20 applies toolbar(removing: .sidebarToggle) to both columns, retaining the custom leading action. It removes Reset's flexible spacer and forced title-and-icon label to restore its prior system icon presentation and placement. Appearance initialization is preserved. The newly built app was opened for this requested visual inspection: the accessibility tree now contains exactly one sidebar action and one Reset action; the screenshot shows the sidebar toggle before the title and Reset in its earlier central action area. Compilation, SDK metadata guard and signature verification passed.

An attempted sidebar click to verify collapse/reopen was rejected by automatic approval review because the user's earlier instruction reserved app testing to the user. No workaround was attempted. Collapse/reopen was not interactively verified. Other controls and settings were not changed during inspection.
