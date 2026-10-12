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


## Build 21 follow-up: Reset at the upper trailing edge

The user clarifies that Reset must be in the upper-right corner. Build 21 preserves the confirmed single leading sidebar toggle and mounted Appearance initialization. SwiftUI continues to supply the native Reset Button and toolbar item. The AppKit SettingsWindow manages NSToolbar's standard flexible-space item immediately before the final action, and clears center-only item grouping. The update hook restores that native spacing when toolbar composition changes; it does not position controls with pixel offsets or redraw any control.

Direct visual observation of the final build confirms Reset at the window's upper-right edge, exactly one sidebar toggle before the title, and white initial Appearance text in the selected native sidebar row. Swift compilation, SDK metadata and package signature verification passed. This turn inspected window presentation only; Reset was not clicked and no unrelated settings or interaction tests were performed.


## Build 22 follow-up: stable toolbar and mode-control layout

The user prohibits further Computer Use, reports Reset flashing between center and trailing positions during rapid sidebar toggles, identifies duplicate Settings entry points, and reports panel movement when switching Glow modes. This turn uses source inspection and compilation only.

Toolbar declarations now keep sidebar toggle and Reset in fixed root-level slots with explicit stable identifiers. Changing sidebar visibility no longer removes an item from one column and inserts it into another. Scoped removal of default sidebar controls is retained, as is native flexible-space alignment. Redundant centered-item writes are avoided. This targets the structural rebuild that required after-update spacing repair; runtime flicker resolution is not established.

The main panel retains only the footer gear as its Settings entry; the More menu no longer duplicates it. The static panel shell no longer observes AppState. Mode control, status/measurement and footer observe their own child regions. Header, measurement, mode selector and footer reserve stable heights; the segmented Picker fills the available width. Mode-dependent text therefore does not change the shell's vertical allocation.

Glow uses native SwiftUI Picker with pickerStyle(.segmented), the style linked in HIG Segmented controls. It remains a single-choice control with five related glow-state options; no custom segmented-button implementation was introduced.

Build 22 passed Swift compilation, SDK metadata guard, whitespace and package signature validation. The app package is built in a separate staging directory to avoid overwriting the running Build 21 app. No Computer Use or interaction testing was performed; rapid sidebar toggling and Glow layout changes remain for user verification.


## Build 23: macOS 27 baseline and SwiftUI-owned panel glass

The user requests the latest macOS 27 native experience. The installed SDK is 27.0; the earlier preview already linked that SDK while deploying to macOS 14. Build 23 explicitly raises the Xcode deployment target, source Info.plist minimum, direct Swift target and linker minimum to 27.0. The compiler rejects SDKs older than 27 and validates both recorded SDK and minimum OS metadata. This is a deliberate compatibility change: Build 23 requires macOS 27 or newer. Raising the deployment target alone is not a guarantee of changed optics.

The panel's material is now native SwiftUI glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24)) within its own hosting hierarchy. AppKit remains responsible for the borderless window and its focus/placement. The NSGlassEffectView wrapper and old popover NSVisualEffectView branch are removed, so only one framework owns the panel material context. Settings actions use native .glass directly without older-control fallbacks. Standard Slider, Toggle and segmented Picker retain the system implementation; no custom thumb, selection pill or nested fake glass is introduced. This migration provides SwiftUI-owned material composition, not runtime proof of the user's reported appearance issue.

Apple's Adopting Liquid Glass documentation describes automatic current-SDK control adoption and dynamic interaction effects; a resting control need not look fully transparent. New APIs should be chosen by semantics, not merely by their introduction version. Glow is a value selector, so its segmented style is retained rather than changing to tab-view navigation.

Compilation, SDK 27.0 and minimum OS 27.0 checks, source whitespace and package signature verification passed. No Computer Use, app launch or interactive testing was performed. Native control optics and panel focus/material behavior remain for user verification.


## Build 24: direct Quit and native segmented tracking

The user reports mode-switch layout stutter persists and asks why the segmented control is not visibly Liquid Glass. Native status alone does not guarantee a permanently transparent resting appearance. The OS chooses system control optics; this build does not add a drawn glass pill or claim visual verification.

Glow now uses macOS 27 NSSegmentedControl via NSViewRepresentable, explicitly configuring valueSelection role, automatic system style, capsule border, single-choice tracking and fillEqually segment distribution. The SwiftUI shell and glass surface remain. Native selection tracking is retained; updateNSView writes selection only when it differs from the already tracked segment. Per-segment system tooltips describe each mode. The representable sizes from system intrinsic height and offered width instead of allowing selection-dependent fitting width to drive the layout.

Source inspection also found that every panel mouse-down called engage again, repeating App activation and makeKeyAndOrderFront during control tracking. Engagement is now idempotent until dismissal. Redundant effective-load/alarm publications are avoided. These changes target actual repeat-focus and native metric update paths; they do not establish that all reported stutter is resolved.

Quit is a directly labeled native SwiftUI glass Button in the header. The one-item More menu is removed. The footer gear remains the sole Settings entry in the panel.

Build 24 compiled with SDK/minimum OS 27.0 and passed metadata, whitespace and signature verification. No Computer Use, app launch or interactive testing was performed. Native material optics and rapid selection behavior remain for user verification.

## Build 25: Always On Top

The user clarified that AOP means Always On Top. The notch glow and controls panel already use elevated window levels; Settings was still a normal window. Settings now defaults to the native NSWindow floating level, with a persistent native SwiftUI “Keep Settings on Top” toggle in Behavior. The controller observes settings changes and updates the existing window immediately, without activating the app, recreating its content or changing the toolbar. Turning the option off restores the normal window level. Reset All restores the default enabled state. This setting applies to Settings, above ordinary app windows in its current Space; it does not change the panel's dismissal behavior or move windows across Spaces.

Liquid Glass appearance remains an open user-reported issue. This build does not replace value selection with a tab-navigation role simply for different optics, add a drawn glass imitation or assert that the visual issue is resolved. The native macOS 27 APIs were rechecked against the installed SDK and Apple's AppKit design presentation. No interactive visual verification is performed at the user's request.

Build 25 compiled with SDK/minimum OS 27.0 and passed package signature verification. No Computer Use, app launch or interaction testing was performed.

## Build 26: hover overlay above the focused application

The user clarified that Always On Top applies to the hover controls panel, not Settings. The Build 25 Settings preference and floating-window changes are removed; Settings returns to its existing normal-window behavior.

The controls panel already used status-window level + 2 and orderFrontRegardless. Its collection behavior, however, only moved it to the active Space on activation, while hover intentionally does not activate PeakGlow. The panel now combines canJoinAllSpaces with canJoinAllApplications, explicitly opts into floating-panel behavior and preserves hidesOnDeactivate = false. The hover hit target also adopts canJoinAllApplications so it can receive hover in the foreground app's eligible fullscreen Space. The overlay level is reaffirmed only when different on presentation. Hover still does not make the panel key or activate the application; click engagement retains keyboard navigation. This uses Apple's documented behavior for overlays joining other apps in full screen and Stage Manager, rather than repeatedly stealing focus or polling frontmost windows.

Reference: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications

Actual foreground-window, fullscreen and Stage Manager interaction remains for user verification. No Computer Use or app launch is performed.

Build 26 passed Swift compilation with SDK/minimum OS 27.0, whitespace checks and package signature verification.

## Build 27: native tabs-role lens and compact Quit

The user supplied a Reddit discussion explicitly identifying NSSegmentedControl.role = .tabs for the desired macOS 27 lens effect. Earlier builds deliberately chose valueSelection for Glow's value semantics, but that did not produce the requested appearance. This build prioritizes the user's explicit visual direction and adopts the public macOS 27 tabs role. The same native control, select-one tracking, equal segment distribution, intrinsic height and guarded selection update remain; no custom selection pill, private API or manual lens animation is introduced. Modes still update the existing glow preview rather than navigating a TabView. The installed Apple SDK declares tabs and valueSelection as separate public roles available since macOS 27.

Quit now uses a small native SwiftUI circular glass button with the SF Symbol power, retaining the Quit PeakGlow tooltip and accessibility label. The header's fixed allocation and direct quit action remain.

Reference supplied by the user: https://www.reddit.com/r/swift/comments/1vbefq1/why_doesnt_nssegmentedcontrol_get_the_macos_26/
Public API: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/role-swift.enum/tabs

The role-specific visual result and animation remain for user verification. No Computer Use, app launch or interaction testing is performed.

Build 27 passed Swift compilation with SDK/minimum OS 27.0, source whitespace checks and package signature verification.
