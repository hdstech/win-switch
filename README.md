# WinSwitch

An AltTab-style window switcher for macOS: press **⌥⇥ (Option+Tab)** to flip
through every open window — across all apps, all Spaces, including minimized
windows — with a thumbnail preview of each.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)

## Features

- **Window-level switching**, not app-level: every window gets its own tile,
  in front-to-back order.
- **Cross-Space**: windows on other Spaces (and fullscreen apps) are listed;
  activating one jumps to that Space (or pulls the window to you as fallback).
- **Minimized windows** appear too, badged, and are unminimized on selection.
- **Live preview**: the highlighted tile is a real-time ScreenCaptureKit
  stream — a playing video plays right in the switcher. Other tiles show
  fresh static screenshots.
- **⌥⇥ semantics**: hold Option, tap Tab to step forward, ⇧⌥⇥ to step back,
  release Option to switch. Arrow keys and mouse clicks also work; Esc cancels.

## Build & run

```sh
make run    # swift build -c release → WinSwitch.app → open it
```

Or manually:

```sh
swift build -c release
```

and wrap `.build/release/WinSwitch` into an app bundle (see the `Makefile`).

The app is a menu-bar agent (no Dock icon); quit it from the menu bar icon.

## Permissions

On first launch macOS will ask for:

- **Screen Recording** — required for window titles, thumbnails and the live
  preview (no titles/images are visible without it).
- **Accessibility** — required to detect/unminimize windows and to raise the
  chosen window within its app.

If you deny either, the app still runs but is degraded (icons instead of
thumbnails; windows may not unminimize/raise). Grant them in
System Settings → Privacy & Security, then relaunch. Because the app is
ad-hoc signed, you may need to re-grant after rebuilding (use the menu-bar
menu for quick links to the right panes).

## How it works

| Task | Mechanism |
|---|---|
| Global hotkey | Carbon `RegisterEventHotKey` (⌥⇥, ⇧⌥⇥) — no permissions needed |
| Enumerate windows | `CGWindowListCopyWindowInfo(.optionAll)` — every space + minimized |
| Window → Space mapping | Private `CGSGetWindowWorkspace` / `SLSWindowCopyWorkspaceID` |
| Switch to another Space | Private `CGSManagedDisplaySetCurrentSpace` (fallback: `SLSMoveWindowsToManagedSpace`) |
| Unminimize / raise | Accessibility (`AXMinimized`, `AXRaise`, `AXFrontmost`), window matched via private `_AXUIElementGetWindow` |
| Static thumbnails | `CGWindowListCreateImage` (reads the offscreen backing store) |
| Live video preview | `SCStream` on the selected `SCWindow` at 30 fps |
| Option-release / Esc / arrows | `CGEventSource.flagsState` / `.keyState` polling — no Input Monitoring needed |

Private SkyLight symbols are resolved via `dlopen`/`dlsym`, so a missing or
renamed symbol on a future macOS degrades gracefully rather than crashing.

## Limitations

- Only the *selected* tile streams live video (one `SCStream` per window would
  be wasteful); everything else is a fresh still.
- Without Accessibility permission, minimized windows can't be restored and
  the per-window raise falls back to `SLSOrderWindow`.
- Windows from `Window Server`-owned UI and sub-50px windows are filtered out.

## License

MIT
