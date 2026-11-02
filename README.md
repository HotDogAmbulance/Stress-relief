# Stress-relief

**8-bit & Pixel-Art Ambient Landscapes for the MacBook Pro Touch Bar — Synchronized with macOS Background Sounds**

> *Status: **Final Version (`final-version-main`)** — Feature-complete and archived. Built for the last generation of Touch Bar MacBook Pros.*

---

## Overview

**Stress-relief** turns the MacBook Pro Touch Bar (`1004 × 30 pt` OLED strip) into a living, breathing 8-bit ambient canvas. Instead of static function keys or distracting buttons, it renders **16 handcrafted procedural pixel-art panoramas** that react in real time to macOS **Background Sounds** (*System Settings → Accessibility → Audio → Background Sounds*).

Whenever you turn on Background Sounds in macOS, the companion LaunchAgent (**Stress-relief Sound Watcher**) automatically wakes **Stress-relief** on your Touch Bar and matches the visual scene and animation pace to the sound and volume you selected. When you turn Background Sounds off, the app exits cleanly with zero background footprint.

### A Note on "Dying Specs" (Why Touch Bar?)

Apple officially discontinued the Touch Bar after the M2 13-inch MacBook Pro, returning to physical function keys across the entire Mac lineup. From a mass-market commercial standpoint, building exclusively for discontinued hardware is a dead end.

From a craft and design standpoint, however, the Touch Bar's ultra-wide `2170 × 60 px` (`1004 × 30 pt @2x`) OLED ribbon is a uniquely intimate hardware artifact. Freed from trying to replace physical `Esc` or `F1–F12` keys, it becomes what it always excelled at being: **a dedicated ambient horizon resting just above your keyboard**—a tiny window of rain, ocean waves, starlight, or passing night trains while you work.

Because the hardware generation is now fixed in time, **Stress-relief** does not need endless feature creep. This release (`final-version-main`) is its completed, permanent form.

---

## 16 Synchronized Sound Themes

| macOS Background Sound | Touch Bar Visual Scene | Grid Resolution |
| :--- | :--- | :--- |
| **Balanced Noise** | Dual-phase cyan & emerald harmonic wave interference | `12 × 402` |
| **Bright Noise** | Three-band high-frequency luminous wave spectrum | `12 × 402` |
| **Dark Noise** | Deep multi-octave Brownian geological strata | `12 × 402` |
| **Ocean** | Sunrise beach, 3-layer teal waves, 5 surfacing sharks, 10 starfish, and 2 scuttling shrimp | `20 × 670` |
| **Rain** | Wind-slanted multi-depth rain curtains with ground splashes | `15 × 502` |
| **Rain on Roof** | Cozy cross-section interior under a rain-drenched roof, warm lamps, cat, and rising smoke | `20 × 670` |
| **Stream** | Flowing creek with mossy boulders, lotus pads, dragonfly, and 7 swimming koi | `20 × 670` |
| **Night** | Deep night sky with twinkling constellations and multi-directional meteors | `15 × 502` |
| **Quiet Night** | Van Gogh *Starry Night* homage with a rare peeking 8-bit frog | `15 × 502` |
| **Fire** | Glowing ember bed, breathing ash bulges, and rising sparks | `15 × 502` |
| **Steam** | Midnight indigo hot-spring vapor with 5 asymmetric steam zones and winking 8-bit cel-shaded portrait | `20 × 670` |
| **Babble** | Dynamic Wassily Kandinsky (*Composition VIII*) geometric canvas rasterized into 8-bit | `15 × 502` |
| **Airplane** | Airliner with contrail & vintage biplane cruising above layered cloud decks | `20 × 670` |
| **Boat** | Coastal lighthouse beam sweeping from starry night into golden sunset with 4 vessels | `20 × 670` |
| **Bus** | Red double-decker London bus cruising past a grey deconstructivist skyline | `20 × 670` |
| **Train** | 6-car 3D mountain express crossing stone viaducts and waterfalls | `20 × 670` |

---

## Architecture & Performance / Security Hardening

```
/Applications/Stress-relief/
├── Stress-relief/
│   ├── MyApp.swift                  # App entry point & NSTouchBar lifecycle
│   ├── TouchBarPrivateAPI.swift     # DFRFoundation bridge (system-modal bar without close box)
│   ├── ColorCache.swift             # Hex/RGB Lerp cache & O(1) 32,768-color LUT for rasterizer
│   ├── ComfortSoundsMonitor.swift   # Zero-overhead CFPreferences reader with binary plist diffing
│   ├── Wave8BitView.swift           # Core 25 FPS renderer & sleep/wake power management
│   └── Wave8BitView+Themes.swift    # Procedural shaders for all 16 themes
├── Stress-relief.xcodeproj/         # Native macOS Xcode project
└── sound-watcher/                   # Companion LaunchAgent & app bundle
    ├── Stress-relief Sound Watcher.app/
    ├── com.gimmick.stress-relief-comfort-follow.plist
    ├── icon/                        # CoreGraphics procedural icon generator
    └── README.md                    # Detailed watcher documentation
```

- **Zero Idle Battery Drain**: Automatically suspends both the `25 FPS` render timer and preference monitor upon `NSWorkspace.screensDidSleepNotification` and `NSWorkspace.willSleepNotification`, and exits completely when Background Sounds is toggled off.
- **Zero Per-Frame Heap Churn**: All `CGColor` objects, gradients, and the 15-bit (`32,768`-color) raster lookup table are pre-allocated and cached. Soft-grid overlays are batched into a single `CGContext.addRects` draw call.
- **VRAM Sized to Hardware**: Backing store is clamped strictly to `1004 × 30 pt` (`2008 × 60 px @2x`).
- **Hardened Watcher**: Locked `PATH`, strict non-symlink validation on app bundles and state files, zero network access, and zero external dependencies.

---

## Simple Installation Guide

### Requirements
- **MacBook Pro with Touch Bar** (2016–2022, Intel or Apple Silicon M1/M2)
- **macOS 14.0 (Sonoma)** or later
- **Xcode** (to build from source)

### 1. Clone & Build the App
Place the repository at `/Applications/Stress-relief` and build the Release bundle:

```bash
git clone https://github.com/HotDogAmbulance/Stress-relief.git /Applications/Stress-relief
cd /Applications/Stress-relief

xcodebuild -project Stress-relief.xcodeproj \
           -scheme Stress-relief \
           -configuration Release \
           -derivedDataPath build \
           build

cp -R build/Build/Products/Release/Stress-relief.app /Applications/Stress-relief.app
cp sound-watcher/icon/AppIcon.icns /Applications/Stress-relief.app/Contents/Resources/AppIcon.icns
```

### 2. Enable Automatic Sync with macOS Background Sounds (Optional, Recommended)
Install the lightweight LaunchAgent so **Stress-relief** opens and closes automatically whenever you toggle macOS Background Sounds:

```bash
cp /Applications/Stress-relief/sound-watcher/com.gimmick.stress-relief-comfort-follow.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gimmick.stress-relief-comfort-follow.plist
```

Now open **System Settings → Accessibility → Audio → Background Sounds** (or add **Hearing** to Control Center / Menu Bar) and toggle **Background Sounds** on.

### Uninstall
```bash
launchctl bootout gui/$(id -u)/com.gimmick.stress-relief-comfort-follow
rm -f ~/Library/LaunchAgents/com.gimmick.stress-relief-comfort-follow.plist
```

---

## Credits

**Stress-relief** is a pure vibe-crafted project:

- **Creator, Vision & Art Direction (Vibe):** **Tùng** ([@HotDogAmbulance](https://github.com/HotDogAmbulance))
- **Co-built & Engineered with:**
  - **Argon** (in Antigravity)
  - **Argon** on `studio.google` (Google AI Studio)
  - **Gemini 3.8 Flash**

