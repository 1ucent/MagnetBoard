# Magnet Board

A small SwiftUI iPhone app whose whole interface **leans toward a real magnet**.

Hold a fridge magnet (a small neodymium ring works best) about 2 cm above the
screen and the tiles get pulled toward it, tilt, and glow hotter the closer it
gets. Move it around and the board follows; take it away and everything springs
back. Dip the magnet toward the glass and the app counts an **air tap**.

The sensing is done by [Magnetic UI / MagnetKit](https://libraries.dev/magnetic)
from Libraries.dev: a ~1 MB on-device model that reads the magnetometer, locates
the magnet on the screen (median error ~1.2 cm), decides whether it is really
there, and recognises air taps. No permission prompt, no network.

```
Magnet app  ──►  MagnetKit (Magnet.mfxl, Accelerate)  ──►  MagnetFrame  ──►  SwiftUI
                 position · presence · pull · toward              tiles, Canvas, HUD
```

## What's inside

| File | Role |
|---|---|
| `MagnetBoardApp.swift` | `@main`, owns the single `MagnetEngine`, dark nav appearance |
| `MagnetEngine.swift` | **The only file that talks to MagnetKit.** Config, `attach`/`detach`/`calibrate`, one `MagnetFrame` per refresh, gesture events, haptics, and a finger-driven demo magnet |
| `ContentView.swift` | The board: `TimelineView(.animation)` → header, presence meter, tiles, status pill, demo puck, event banner |
| `MagneticTile.swift` | Wraps any control, measures itself, applies offset / tilt / scale / glow from the frame |
| `BoardControls.swift` | Power switch, level stepper, brightness slider, segmented field-mode chips, air-tap counter |
| `FieldOverlay.swift` | `Canvas` beam from the magnetometer to the magnet, 1-σ spread ring, pulsing puck, tap ripples |
| `HUDView.swift` | Presence, distance, height, spread, pull, too-close warning |
| `SettingsSheet.swift` | Demo mode, magnet north face, recalibrate, model setup notes |
| `Theme.swift` | Palette, metrics, shared card surface |
| `tools/make_icon.py` | Regenerates `AppIcon-1024.png` (pure Python, no dependencies) |

## Requirements

- iOS **17.0+**, Xcode **15+**
- A physical iPhone (the Simulator has no magnetometer — use demo mode there)
- A magnet. Any fridge magnet works; a small neodymium ring is best

## Getting started

1. **Open `MagnetBoard.xcodeproj`.** The Swift package is already referenced
   (`https://github.com/Jakubantalik/Libraries.dev`, branch `main`, product
   `MagnetKit`); Xcode resolves it on first open.
2. **Add the model.** Download `Magnet.mfxl` (2 MB) from
   [libraries.dev/magnetic](https://libraries.dev/magnetic) → **Model**, then drag
   it into the `MagnetBoard` group and tick **Copy Bundle Resources**.

   The model is *not* in the Swift package. Without it the app still builds and
   runs, shows **NO MODEL** in the status pill, and demo mode still works.
3. Pick your Team under **Signing & Capabilities**, then run on your iPhone.

`./build_ipa.sh` produces an unsigned `build/MagnetBoard.ipa` for AltStore /
Sideloadly / TrollStore. Set `TEAM_ID=…` to sign instead.

## Using it

| Gesture | What happens |
|---|---|
| Hold the magnet over the board | Tiles pull toward it, tilt, and glow; the beam and puck follow |
| Move it closer / farther | `pull` grows / shrinks, the glow and background respond |
| Dip it quickly toward the glass | Counted as an **air tap** — ripple, haptic, counter +1 |
| Dart toward / yank away | `PUSH` / `PULLED AWAY` banner with the speed in cm/s |
| Swipe across the screen fast | `SWIPE` banner (above 1,500 pt/s) |
| Keep it too close | **TOO CLOSE** warning — past ~2,000 µT the phone gets magnetised |

Settings (top-right) has **Demo magnet** for the Simulator: drag the orange puck,
tap it for an air tap. Leaving demo mode re-attaches the real magnetometer.

## How the library is used

MagnetKit's own API, exactly as documented:

```swift
let magnet = MagnetSource.shared
magnet.config.locatorEnabled = true
magnet.config.sensorPosition = CGPoint(x: 70, y: 86)   // magnetometer, window points
magnet.config.magnetFace = 1                            // +1 north toward the user
magnet.attach()                                         // onAppear; detach() on disappear

let r = magnet.reading(now: now)                        // once per TimelineView frame
r.screenPosition   // CGPoint?  global points
r.screenSpread     // 1-σ uncertainty, points
r.height           // cm above the glass
r.presence         // 0…1 is a magnet really there
r.pull, r.toward   // closeness and unit direction (works without the locator)
r.distance, r.approachSpeed, r.tooClose, r.calibrating

magnet.addGestureHandler { g in
    switch g {
    case .tap(let at): break          // at: global points
    case .push(let speed): break      // cm/s
    case .pullAway(let speed): break  // cm/s
    case .swipe(let dir, let speed): break
    }
}
```

The app maps that onto a single plain struct per frame, so the views are cheap
and the magnet maths lives in one place:

```swift
func influence(at center: CGPoint, reach: CGFloat) -> CGFloat {
    guard let position else { return 0 }
    let d = max(1, hypot(position.x - center.x, position.y - center.y))
    let near = max(0, 1 - d / reach)
    return CGFloat(presence) * near * near      // presence fades effects out
}
```

## Tuning

- **Sensor spot** — `MagnetSupport.sensorPosition` in `MagnetEngine.swift` is for an
  iPhone 15 Pro (70, 86 pt). Move it a few points for another model.
- **Reach / travel / tilt** — per-tile arguments on `MagneticTile` (`reach`,
  `travel`, `tilt`, `glow`); defaults come from `Theme.reach`.
- **Magnet face** — Settings → *North pole faces the screen* flips
  `config.magnetFace` if the puck mirrors your hand.
- **Recalibrate** after putting the phone on a steel table, a laptop or a MagSafe
  puck — those shift the phone's own field.

## Licensing

- App code in this repository: yours to use.
- **MagnetKit code**: MIT.
- **`Magnet.mfxl` model**: Libraries.dev Model License — free for development,
  prototypes and non-commercial apps. A commercial release needs a Libraries.dev
  plan. Ship the file inside the app bundle, never in a public repository.

## Note on verification

This was written on Linux, where Xcode is unavailable, so the project has not
been compiled here. The Xcode project, plists, asset catalogs and scheme were
checked structurally (brace/paren balance, every object ID resolved, JSON/plist
valid), and the Swift sources were reviewed against the published MagnetKit API.
If the package layout ever changes, the `#if canImport(MagnetKit)` guards mean
you get a build with the demo puck instead of a wall of errors.
