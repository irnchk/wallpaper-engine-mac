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
- **Automatic Light/Dark wallpapers** — assign separate Light/Day and Dark/Night wallpapers and switch by macOS appearance or a simple day/night schedule.
- **Interactive image objects** — add album covers or custom images on top of a wallpaper, then enable edit mode to click and drag them into place.
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
- **`Add Live2D Web Object...`** copies the folder containing a local Live2D/Cubism Web HTML entry file and renders it as an interactive WebKit object. The Live2D runtime is not bundled; use assets you are licensed to run.
- **`Edit / Interact With Objects`** raises the wallpaper into an edit layer so objects can be clicked and dragged. Turn it off to return the wallpaper behind desktop icons.
- **`Remove Object`** removes an object from `project.json` and deletes the app-copied asset when it lives under `InteractiveObjects/`.
- **`Reset Object Positions`** clears saved drag positions for the current wallpaper.

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
- **`Import Local Workshop Folder`** imports the local `steamapps/workshop/content/431960` folder when Steam has already installed subscribed items.
- **`Download Item with SteamCMD...`** tries an anonymous SteamCMD download into the app support folder, then imports the item if Steam permits the download.

Some Workshop items require the user to own Wallpaper Engine or be logged into Steam, so SteamCMD may fail by design.

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
