# SpaceName — plan

Menu bar app that names each Mission Control Space and styles the label.

## Build approach
- Swift Package (no Xcode required — only Command Line Tools are installed).
- `scripts/build_app.sh` runs `swift build`, then assembles `build/SpaceName.app`
  (Info.plist with `LSUIElement = true`) and ad-hoc signs it. A real bundle is
  needed for LSUIElement, SMAppService, and a stable Accessibility grant.
- Target macOS 14+, Swift 6 toolchain in Swift 5 language mode.

## Files
| File | Role |
|---|---|
| `Package.swift` | SwiftPM manifest (one executable target) |
| `Resources/Info.plist` | Bundle metadata, LSUIElement |
| `scripts/build_app.sh` | Build + bundle + sign |
| `Sources/SpaceName/main.swift` | App entry |
| `Sources/SpaceName/AppDelegate.swift` | Wires services together |
| `Sources/SpaceName/SpaceProvider.swift` | **All private CGS/SkyLight calls live here** |
| `Sources/SpaceName/SpaceModel.swift` | `Space` struct (uuid, index, display, isFullscreen, appName) |
| `Sources/SpaceName/StatusItemController.swift` | NSStatusItem + attributed title |
| `Sources/SpaceName/PanelController.swift` | Dropdown panel host (step 2) |
| `Sources/SpaceName/Views/*.swift` | SwiftUI rows, editor, settings (step 2+) |
| `Sources/SpaceName/SpaceStore.swift` | Per-UUID name/color/bold/italic persistence (step 2) |
| `Sources/SpaceName/SpaceSwitcher.swift` | CGEvent shortcut switching + permission checks (step 2) |
| `Sources/SpaceName/LoginItem.swift` | SMAppService wrapper (step 2) |
| `README.md` | Build/run, private API notes (step 3) |

## Milestones
1. **Prototype**: status item shows "Desktop N" for the current Space on the
   menu-bar display, updates on `activeSpaceDidChangeNotification`.
2. Dropdown panel with static rows → inline rename + persistence → color and
   bold/italic + contrast warning → switch-Space button → launch at login.
3. README.

## Decisions
- Panel host: borderless `NSPanel` + `NSVisualEffectView` (dark, rounded).
- Persistence: JSON in Application Support, keyed by Space UUID.
- Space switching: the user's Mission Control shortcuts via CGEvent; no CGS
  switching (see README).
