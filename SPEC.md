# WindowEdgeStash — specification

**Tagline:** Park any window at a screen edge where it slides out when your pointer touches that edge.

**Category:** Window Management

**Inspired by (paid):** Rectangle Pro ($9.99 one-time)

**Frameworks:** SwiftUI, AppKit, ApplicationServices, CoreGraphics, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does. Rectangle Pro is the paid edition of the popular free Rectangle snapper and sells for roughly 10 dollars with a ten-day trial. One of its headline Pro features is stash, where a window is tucked against a screen edge and slides back out when the cursor touches that edge. The free parent project is very widely recommended in window management roundups, and the Pro upsell proves people pay for this behavior. Our clean-room version builds only the stash feature as a focused tool.

(2) Feature set. A hotkey stashes the focused window to the nearest screen edge, leaving a thin visible strip of a few points. Moving the pointer onto that strip slides the window fully into view over a short animation. Moving the pointer away, or switching focus, slides it back. A second hotkey un-stashes the window and restores its original frame. Multiple windows can be stashed, even on the same edge, with strips stacked in order. Settings control the visible strip width, the reveal delay in milliseconds, whether to hide on focus loss, and an animation duration.

(3) UI spec. MenuBarExtra with a sidebar-style icon. The menu lists currently stashed windows by app and title, each with an Unstash action, plus Unstash All, Settings and Quit. Settings fields: stash hotkey, unstash hotkey, strip width slider from 2 to 20 points, reveal delay, animation duration, hide-on-focus-loss toggle and launch at login toggle. A subtle highlight line appears on the screen edge when the pointer hovers a strip. Empty state: the menu displays No stashed windows and a hint describing the hotkey. Missing permission shows a Grant Accessibility row.

(4) Technical approach. Use AXUIElement on the focused window to read its position and size and store the original frame together with the owner process identifier and the window element. Computing the target frame places the window so that only the strip remains on the chosen screen, which can legally extend past the display edge. Track the pointer with an NSEvent global monitor for mouse moved events, which needs no permission beyond Accessibility, and compare its location against the strip rectangles using a Timer at about 30 hertz as fallback. Animate by stepping the position attribute over time with a display-linked timer such as CVDisplayLink or a plain Timer, using an ease-out curve. Register hotkeys with Carbon RegisterEventHotKey. Persist settings in AppStorage. The stash list lives only in memory, because window elements cannot be restored after quit, but on termination every stashed window is unstashed. Launch at login through SMAppService. Request Accessibility trust with the prompt option.

(5) Edge cases. When the target app quits or the window closes, detect an invalid AXUIElement error and drop it from the list. Windows that refuse to leave the screen because the system clamps them need a fallback that shrinks the strip and tries again. Prevent stashing the app's own windows and full-screen windows. On display configuration changes, unstash everything. Handle the Mission Control and Spaces transitions by pausing the pointer monitor while the active Space changes. Avoid accidental reveals by requiring the pointer to dwell for the configured delay.
