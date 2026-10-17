# SpaceName

A macOS menu bar app that shows which Mission Control Space you're on, with a
custom name, color, and bold/italic style per Space.

- Click the menu bar item for a dropdown listing every Space on the display that
  has the menu bar.
- Click a name to rename it inline (Return saves, Esc cancels). While editing,
  pick a color and bold/italic, with a live light/dark menu bar preview and a
  warning when the color is hard to read.
- Click ↗ to switch to that Space.
- Mission Control (F3) shows your names and styles in place of "Desktop N".
- Gear button: Launch at Login, Show Names in Mission Control, shortcut and
  permission settings, Quit.

Requires macOS 14+. No Dock icon (`LSUIElement`).

## Build and run

Only the Xcode Command Line Tools are needed.

```bash
scripts/build_app.sh            # release build → build/SpaceName.app
scripts/build_app.sh debug      # debug build
open build/SpaceName.app
```

To quit: gear button › Quit SpaceName, or `pkill -x SpaceName`.

### Signing and the Accessibility permission

Switching Spaces posts keyboard events, which needs **Accessibility** permission.
macOS ties that permission to the app's code signature.

- **Ad-hoc signing (default)**: the signature changes on every rebuild, so the
  permission stops working after each build. In practice macOS can also keep
  recording an older build's signature even after you remove and re-add the app.
- **Self-signed certificate (recommended for development)**: create one once and
  the permission survives rebuilds. In Keychain Access choose
  *Certificate Assistant › Create a Certificate…*, name it `SpaceName Dev`, set
  Identity Type to *Self-Signed Root* and Certificate Type to *Code Signing*.
  `build_app.sh` picks it up automatically (or set `SIGN_IDENTITY` to use another).
  After switching to the certificate, remove SpaceName from
  *Privacy & Security › Accessibility* with **−** and grant it again once.

### Switching setup

The ↗ button presses your Mission Control shortcuts, using the key bindings
actually configured in *System Settings › Keyboard › Keyboard Shortcuts… ›
Mission Control*:

1. **Switch to Desktop N** (off by default): jumps straight there. Turn these on
   for the best experience.
2. **Move left/right a space** (on by default): used as a fallback, stepping
   one Space at a time. This is also the only way to reach full-screen app Spaces.

If neither is available, or permission is missing, the panel shows a banner that
links to the right settings page.

### Launch at login

Uses `SMAppService.mainApp`. It registers the bundle at its current path, so move
`SpaceName.app` to `/Applications` first if you want it to survive rebuilds or
cleanups of `build/`.

### Names in Mission Control

macOS draws the "Desktop N" labels itself and can't be told to use other names.
SpaceName instead places a click-through window above Mission Control with a
name tag over each renamed Space's label (see
[the mockup](docs/mission-control-overlay-mockup.png)). It finds the labels
through the Dock's accessibility tree, so it needs the same Accessibility
permission as switching. While Mission Control is closed it checks for it four
times a second; while open it follows the labels 30 times a second so tags
keep up when the bar expands on hover. Turn it off in the gear menu.

## Data

Names and styles are stored in
`~/Library/Application Support/SpaceName/spaces.json`, keyed by each Space's
UUID. Reordering, adding, or removing Spaces never attaches a name to the wrong
Space. Full-screen app Spaces have no UUID, so they are labeled with the app's
name and can't be renamed.

## Private APIs

macOS has no public API for Spaces. All private calls are in
[`SpaceProvider.swift`](Sources/SpaceName/SpaceProvider.swift), declared with
`@_silgen_name` so a future macOS change only needs fixing in one file.

| Function | Used for |
|---|---|
| `CGSMainConnectionID` | Connection to the window server |
| `CGSGetActiveSpace` | ID of the active Space |
| `CGSCopyManagedDisplaySpaces` | Every display's Spaces: ID, UUID, type (desktop or full screen), current Space |
| `CGSCopyActiveMenuBarDisplayIdentifier` | Which display has the menu bar, when displays have separate Spaces |

These come from SkyLight and are re-exported by CoreGraphics. They are not
App Store safe.

Other semi-private details:

- [`DockMissionControl.swift`](Sources/SpaceName/DockMissionControl.swift) reads
  the Dock's undocumented accessibility identifiers (`mc`, `mc.display`,
  `mc.spaces.list`, `AXDisplayID`) to find the Spaces bar. A macOS update that
  changes them only needs fixing there.
- Mission Control shortcut bindings are read from the
  `com.apple.symbolichotkeys` preferences (`AppleSymbolicHotKeys`; IDs 79/81 for
  move left/right, 118–133 for Desktop 1–16).
- "Desktop N" shortcut numbers count desktops across all displays in the order
  `CGSCopyManagedDisplaySpaces` returns them. This has only been checked on a
  single display.

### Why not switch Spaces with CGS directly?

Private calls such as `CGSManagedDisplaySetCurrentSpace` (or the
`CGSShowSpaces`/`CGSHideSpaces` pair) change what the window server shows, but
not the Dock's idea of the current Space. Dock owns Mission Control. The result
is a desynchronized state: the wrong windows stay visible or get focus, Mission
Control and the menu bar show the old Space, and the next real switch can jump
unexpectedly. Tools that switch Spaces reliably this way (for example yabai)
inject code into Dock.app, which requires partially disabling System Integrity
Protection. Posting the user's own Mission Control shortcuts is slower and needs
Accessibility permission, but it goes through Dock and stays consistent.

## Layout

```
Package.swift                 SwiftPM manifest
Resources/Info.plist          Bundle metadata (LSUIElement)
scripts/build_app.sh          Build, bundle, sign
Sources/SpaceName/
  SpaceProvider.swift         Private CGS calls (only file using private API)
  SpaceModel.swift            Space / SpaceSnapshot
  SpaceStore.swift            JSON persistence keyed by UUID
  LabelStyle.swift            Fonts, colors, contrast check
  SpaceSwitcher.swift         Shortcut lookup and CGEvent posting
  DockMissionControl.swift    Reads Mission Control's Spaces bar (Dock internals)
  MissionControlOverlay.swift Name tags drawn over Mission Control
  LoginItem.swift             SMAppService wrapper
  AppModel.swift              Live state + inline edit state
  AppDelegate.swift           Wiring and Space-change notifications
  StatusItemController.swift  Menu bar item
  PanelController.swift       Borderless blurred dropdown panel
  Views/                      SwiftUI rows, rename field, style editor, settings menu
```
