# Changelog

All notable changes to yabai-dockstack. Full release notes and downloads live on
the [GitHub Releases](https://github.com/z20240/yabai-dockstack/releases) page.

## v0.3.0 — 2026-10-19

- **Drag windows between spaces** — the search switcher now shows one card per
  space (empty spaces included), grouped per display with the space you're on
  marked "Current", and the window strip opens empty spaces as drop
  slots while dragging; drop a window on another space to move it there, even
  from a space you're not on. Scripting addition → `yabai -m window --space`;
  SIP on → focus the window and walk it over with the simulated gesture. You end
  on the destination space with the window focused. The search switcher's
  hotkey can now be recorded on the Switcher tab.
- **Project-aware window labels** — windows of the same app are labelled by
  what tells them apart: VS Code / Cursor / Windsurf → workspace, JetBrains →
  project, terminals → current folder, otherwise the part of the title that
  differs. Shown first (bold) in switcher captions, Dock previews, the window
  menu and the window strip; the full title is on hover.
- **Window strip** (opt-in) — one strip per display under the menu bar listing
  that display's windows (icon + project-aware label, divider between spaces);
  click to jump, hover for title and space, resizable from Settings, "+N"
  overflow opens the menu; hidden over native-fullscreen spaces.
- **Hover to open the window menu** (opt-in).
- **Dock previews match the rest of the app** — same frosted panel as the
  switcher, colours follow light/dark mode (thanks @Signynt, #5).
- **⌃-drag to reorder a stack** from its indicator (on by default; uses yabai
  `--swap`, works without the scripting addition).
- **Hyper Key** (opt-in) — Caps Lock / right ⌘ / ⌥ / ⌃ → ⌃⌥⌘(⇧), with quick
  press (Escape / toggle Caps Lock) and an optional ✦ display; restores the key
  on quit, SIGTERM, and the next launch after a crash.
- **Fixed: clicking tray-closed apps did nothing** — Gather, Surfshark and
  similar apps keep their closed window listed without an AX reference, so yabai
  can't focus it; the app is now reopened instead, which brings that window back.

## v0.2.16 — 2026-10-14

- **Click-through stack indicator** — new Settings option: clicks pass through
  the indicator to the window underneath (e.g. its close button); hover tooltips
  and click-to-focus are turned off. Off by default. ([#2](https://github.com/z20240/yabai-dockstack/issues/2))
- **Fixed stale / wrong stack indicators** — a sticky window (shown on all
  spaces) no longer makes a hidden space count as visible, so its stacks aren't
  drawn over the current one; indicators are no longer reused across spaces, so
  they don't linger after a stack is closed or unstacked.
- **More reliable SIP-free space moves** — the simulated drag verifies the window
  actually lifts and probes grab points, aborting cleanly instead of bouncing.

## v0.2.15 — 2026-07-14

- **Instant close sync** — closing a window from the Dock preview or the switcher
  removes its cell immediately (optimistic update), instead of a stale snapshot
  lingering until a re-hover.
- **Switcher: ⌘W / ⌘Q** — close the selected window / quit its whole app, in both
  hold-to-cycle and sticky modes.
- **Dock preview: last window quits the app** — ✕ on an app's last window
  terminates the app itself, so apps that merely hide on window close (Music, …)
  actually exit.

## v0.2.14 — 2026-07-14

- **Close from the Dock preview** — hovering a thumbnail reveals an ✕ that closes
  that window via yabai; the popover rebuilds in place.

## v0.2.13 — 2026-07-13

- **Single-instance guard** — a second copy (duplicate login items, session
  restore) now detects the first and exits, instead of two menu-bar icons
  fighting over the socket and event tap.

## v0.2.12 — 2026-07-13

- **AltTab-style window switcher** — hold **⌥⇥** to cycle every window on every
  space (thumbnails, most-recently-used order); **⌥`** for the current app only;
  Shift reverses, arrows navigate, W/✕ closes, Esc cancels, release to switch.
  Optional capture of the system **⌘⇥**.
- Three appearances (thumbnails / app icons / title list) with auto-sizing, a
  type-to-search sticky mode, per-scope hotkeys, and a new **Settings → Switcher**
  tab (en / 繁體中文 / 日本語).
- Fix: bundled helper scripts now resolve in universal (xcodebuild) builds —
  fresh installs previously couldn't install script-backed hotkeys.

## v0.2.11 — 2026-07-06

- **Open window menu** hotkey action (default ⌃,) + **quick-select keys** (1–9, 0,
  letters) on every window row while the menu is open.
- Fix: recorded punctuation hotkeys emit uppercase hex keycodes (skhd rejects
  lowercase).

## v0.2.10 — 2026-07-05

- **Full UI localization** — English / 繁體中文 / 日本語, with an in-app language
  picker (default: follow the system), guarded by string-table parity tests.
- SF Symbol icons next to every hotkey in the Keyboard pane.

## v0.2.9 — 2026-07-04

- Fix: cross-display space moves for tiled windows (float for the journey,
  re-tile on arrival).

## v0.2.8 — 2026-07-04

- **SIP-free space moves** — the send-to-space hotkeys (⌃⌘←/→, ⌃⌘1–9) work with
  SIP fully enabled by simulating the native drag + Mission Control gesture;
  the instant yabai path is still used when the scripting addition is loaded.

## v0.2.7 — 2026-06-30

- **Import existing config** — recognized hand-written `~/.yabairc` / `~/.skhdrc`
  bindings are pulled into the managed region (originals commented out), so the
  Settings UI becomes the single source of truth.

## v0.2.6 — 2026-06-30

- yabai Settings pane layout finally correct; Settings window title shows the
  app version. (v0.2.3–v0.2.5 were intermediate attempts at the same layout bug.)

## v0.2.2 — 2026-06-30

- Swapped **Float** / **Off** semantics to match their labels (Float = all
  windows float with floating-mode shortcuts; Off = yabai hands off entirely).

## v0.2.1 — 2026-06-30

- Fix: Default layout **Off** actually turns yabai management off.
- **⚙️ Edit raw file** opens rc files in a GUI editor (`open -t`).

## v0.2.0 — 2026-06-30

- **Settings UI for yabai & skhd** — three tabs (Appearance / yabai / Keyboard):
  layout, gaps & padding, window rules, and a Raycast-style hotkey list with
  conflict detection. Writes only to a clearly-marked managed region in your rc
  files, backs up to `.bak`, and never applies without pressing **Apply**.

## v0.1.4 — 2026-06-28

- Fix: Dock previews match apps by **bundle id** (VSCode's Dock name differs
  from yabai's app name).

## v0.1.3 — 2026-06-28

- First-run **yabai setup guide** when yabai isn't found.

## v0.1.2 — 2026-06-28

- Ad-hoc code signing so the Accessibility / Screen Recording grants stick.

## v0.1.1 — 2026-06-28

- Permissions section in Settings (live ✓/✗ + Grant… buttons); universal binary
  (Apple Silicon + Intel).

## v0.1.0 — 2026-06-28

- First release: **stack indicators**, **cross-space window menu**, and **Dock
  window previews** for yabai on macOS 14+.
