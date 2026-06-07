<div align="center">

<img src="Resources/AppIcon.png" alt="WallpaperEngineMac icon" width="128" height="128" />

# WallpaperEngineMac

**Native macOS menu bar app for playing locally owned Wallpaper Engine-style video wallpapers.**

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![UI](https://img.shields.io/badge/menu%20bar-AppKit%20%2B%20AVFoundation-lightgrey)
![Status](https://img.shields.io/badge/status-MVP-success)

**English** · [한국어](README.ko.md)

</div>

<p align="center">
  <img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="City Pop live wallpaper sample" width="860" />
</p>

> Plays the wallpaper assets you already own behind your desktop icons — hardware-decoded, battery-aware, and quiet by default.

---

## ✨ Highlights

- **Imports Wallpaper Engine layouts** — a workshop folder such as `Steam/steamapps/workshop/content/431960/`, an individual wallpaper folder containing `project.json`, a lone `project.json`, or a direct `.mp4` / `.m4v` / `.mov` file.
- **Lightweight library window** — parses `project.json` metadata and shows downsampled preview thumbnails for supported and unsupported projects.
- **Plays behind your desktop icons** on every connected display via `AVQueuePlayer` + `AVPlayerLooper` (VideoToolbox hardware decoding).
- **GIF scene fallback playback** — plays Workshop GIF template scenes that provide an animated `preview.gif`.
- **Automatic Light/Dark wallpapers** — assign separate Light/Day and Dark/Night wallpapers and switch by macOS appearance or a simple day/night schedule.
- **Interactive image objects** — add album covers or custom images on top of a wallpaper, then enable edit mode to click and drag them into place.
- **Audio responsive Workshop support** — detects Workshop metadata such as audio reactive / visualizer / spectrum and automatically enables the reactive overlay; local `web` wallpapers are rendered through WebKit.
- **Battery-first power management** — pauses when the screen locks, displays sleep, Low Power Mode is on, on battery (optional), the user pauses, or the wallpaper window is occluded.
- **Frees decoder resources** after a long pause and recreates playback on resume.
- **Muted by default**, with a one-click toggle.
- Ships with a generated `AppIcon.icns` under `Resources/`.

---

## 🌗 Automatic Light / Dark switching

Assign a pair and let the app follow your system appearance or a day/night schedule.

<table>
  <tr>
    <th align="center">☀️ Light / Day</th>
    <th align="center">🌙 Dark / Night</th>
  </tr>
  <tr>
    <td><img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="Light/Day wallpaper" width="420" /></td>
    <td><img src="SampleWallpapers/city-pop-dark-4k-aesthetic-city-night/preview.jpg" alt="Dark/Night wallpaper" width="420" /></td>
  </tr>
  <tr>
    <td align="center"><code>city-pop-a-long-vacation-upscaled-4k</code></td>
    <td align="center"><code>city-pop-dark-4k-aesthetic-city-night</code></td>
  </tr>
</table>

In the menu bar app, open **`Automation`**:

- Use **`Set Current as Light/Day`** and **`Set Current as Dark/Night`** (or the matching buttons in the library window).
- Pick **`Follow System Appearance`** to mirror macOS Light/Dark Mode.
- Pick **`Follow Day/Night Schedule`** to switch at the built-in 06:00 and 18:00 boundaries.

---

## 🧩 Interactive objects

Use **`Interactive Objects`** from the menu bar app to place media objects over the active wallpaper:

- **`Add Image Object to Current Wallpaper...`** copies the selected image into the active project and adds it to `project.json`.
- **`Add Video Object to Current Wallpaper...`** adds a muted looping `.mp4`, `.m4v`, or `.mov` object above the wallpaper.
- **`Add Live2D Web Object...`** copies the folder containing a local Live2D/Cubism Web HTML entry file and renders it as an interactive WebKit object. The copied bundle is loaded through a local-only app scheme, network resources are blocked, and the page/canvas background is forced transparent. The Live2D runtime is not bundled; use local runtime files and assets you are licensed to run.
- **`Edit / Interact With Objects`** raises the wallpaper into an edit layer so objects can be clicked and dragged. Press `Esc` or click outside the objects to return the wallpaper behind desktop icons.
- **`Remove Object`** removes an object from `project.json` and deletes the app-copied asset when it lives under `InteractiveObjects/`.

Use the main menu's **`Audio Responsive`** toggle to show the reactive overlay. Imported Workshop items whose metadata says they are audio reactive, music responsive, visualizers, spectrums, or similar are marked **`Audio Responsive`** in the library and enable the overlay automatically when applied. For compatible scene packages, the app extracts the real background texture from `scene.pkg` and recreates recognized creator-configured audio bar styles, including color, bar count, spacing, lower/upper bounds, circle angles, and bottom/top/side/center/stereo/circle placement from **Simple Audio Bars**. Local `web` wallpapers are rendered through WebKit and receive a lightweight `wallpaperRegisterAudioListener` bridge based on the same audio level. macOS may ask for Screen Recording permission because system audio capture is provided by ScreenCaptureKit.

If macOS keeps denying audio capture after you granted permission, quit the app, remove or reset the stale **Screen & System Audio Recording** entry for `local.wallpaper-engine-mac`, reopen the exact `.app` bundle, and grant it again. Locally rebuilt ad-hoc signed apps can get a new code hash, so old TCC grants may not match the fresh build.

Projects can also define objects directly:

```json
{
  "interactive": {
    "objects": [
      {
        "id": "album-cover",
        "type": "albumArt",
        "title": "Album Cover",
        "file": "InteractiveObjects/cover.jpg",
        "frame": { "x": 0.68, "y": 0.24, "width": 0.18, "height": 0.18 },
        "cornerRadius": 12,
        "draggable": true
      }
    ]
  }
}
```

Frame values are normalized to the screen: `x` and `y` start at the top-left, and `width` / `height` are fractions of the display.

---

## 🧰 Steam Workshop helper

The app does not bypass Steam or redistribute Workshop files. The **`Steam Workshop`** menu provides helper actions around official Steam paths:

- **`Open Wallpaper Engine Workshop`** opens the public Workshop page for Wallpaper Engine.
- **`Open Workshop Item...`** accepts a Workshop URL or published file ID and opens it through Steam.
- **`Import Local Workshop Folder`** imports the local `steamapps/workshop/content/431960` folder when Steam has already installed subscribed items. This is the most reliable path: subscribe in Steam first, wait for the download, then import.
- **`Download Item with SteamCMD Login...`** downloads with a Steam account that owns Wallpaper Engine. Credentials are passed to local SteamCMD for that one run and are not stored by the app.

Wallpaper Engine is a paid Steam app, so Workshop downloads normally require account login. Deleted, hidden, incompatible, age-gated, or region-restricted items can still fail even with account login.

Audio responsive Workshop projects are supported through the app's overlay, scene package extraction, and web audio bridge. Native Wallpaper Engine scene packages (`.pkg`) are imported as playable entries, but they are not executed as a full engine yet; supported scene items use extracted textures, TEX conversion for common RGBA/DXT + LZ4 textures, animated GIF reconstruction for GIF template scenes, and recognized audio effects when available. Packages that use an unknown texture layout still show a scene-package placeholder instead of being handed to the video player. The package reader accepts `PKGV****` archives that keep the known entry-table layout, but dynamic text objects such as clocks and dates are intentionally ignored until full scene composition exists. Tiny square scene previews, such as Workshop icon GIFs, are ignored as playable fallbacks so they are not accidentally stretched across the desktop.

---

## 🖼️ Bundled sample wallpapers

These are arranged as Wallpaper Engine-style video projects so you can import them directly for a quick local test.

<table>
  <tr>
    <td width="50%"><img src="SampleWallpapers/ambient-test-loop/preview.jpg" alt="Ambient test loop" width="100%" /></td>
    <td width="50%"><img src="SampleWallpapers/mixkit-abstract-macro-fluid-background/preview.jpg" alt="Abstract macro fluid background" width="100%" /></td>
  </tr>
  <tr>
    <td align="center"><b>Ambient Test Loop</b><br/><code>SampleWallpapers/ambient-test-loop</code><br/><sub>4K · 10s · 30 fps</sub></td>
    <td align="center"><b>Abstract Macro Fluid</b><br/><code>SampleWallpapers/mixkit-abstract-macro-fluid-background</code><br/><sub>1080p · ~13s</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="City pop light" width="100%" /></td>
    <td width="50%"><img src="SampleWallpapers/city-pop-dark-4k-aesthetic-city-night/preview.jpg" alt="City pop dark" width="100%" /></td>
  </tr>
  <tr>
    <td align="center"><b>City Pop — A Long Vacation</b> ☀️<br/><code>city-pop-a-long-vacation-upscaled-4k</code><br/><sub>Upscaled 4K · 60 fps</sub></td>
    <td align="center"><b>Aesthetic City at Night</b> 🌙<br/><code>city-pop-dark-4k-aesthetic-city-night</code><br/><sub>4K · 30 fps</sub></td>
  </tr>
</table>

---

## 🚀 Run

```sh
swift run WallpaperEngineMac
```

The app appears in the menu bar. Use **`Import Folder or Video`** to add local assets, then apply a supported video wallpaper from the menu or the library window.

## 🧪 Test

```sh
swift run WallpaperEngineSmokeTests
```

---

## 📦 Project layout

```
WallpaperEngineMac/
├── Sources/
│   ├── WallpaperEngineCore/   # project.json parsing, library scanning
│   ├── WallpaperEngineMac/    # menu bar app, renderer, power manager
│   └── WallpaperEngineSmokeTests/
├── SampleWallpapers/          # importable sample video projects
├── Resources/                 # AppIcon
└── Scripts/build-app.sh       # bundles a .app
```

---

## 🎬 Credits & licensing

Each sample folder ships a `SOURCE.md` with full attribution. Summary:

| Sample | Source | License / Note |
| --- | --- | --- |
| Ambient Test Loop | Pixabay 4K ambient loop | Local test fixture |
| Abstract Macro Fluid | [Mixkit](https://mixkit.co/free-stock-video/abstract-macro-fluid-background-101740/) | [Mixkit Free License](https://mixkit.co/license/#videoFree) |
| City Pop — A Long Vacation | [DesktopHut](https://www.desktophut.com/City-Pop-A-Long-Vacation-Live-Wallpaper) | Personal local use; upscaled |
| Aesthetic City at Night | [MotionBgs](https://motionbgs.com/aesthetic-city-at-the-night) | Rights remain with original creators |

This app does **not** download or redistribute Wallpaper Engine workshop content. It only plays assets the user has already obtained and imported locally. Sample wallpapers are bundled for local testing only — please respect each source's terms before reusing them.
