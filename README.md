# WallpaperEngineMac

Native macOS menu bar app for playing locally owned Wallpaper Engine-style video assets.

## Current MVP

- Imports a Wallpaper Engine workshop folder such as `Steam/steamapps/workshop/content/431960/`, an individual wallpaper folder containing `project.json`, a `project.json` file, or a direct `.mp4` / `.m4v` / `.mov` file.
- Parses `project.json` metadata, shows downsampled preview thumbnails, and lists supported and unsupported projects in a lightweight library window.
- Plays supported video wallpapers behind desktop icons on every connected display through `AVQueuePlayer` + `AVPlayerLooper`.
- Can assign separate Light/Day and Dark/Night wallpapers, then switch automatically by macOS appearance or by a simple day/night schedule.
- Pauses playback when the screen locks, displays sleep, low power mode is enabled, battery pause is enabled, the user pauses, or the wallpaper window is occluded.
- Releases video decoder resources after a long pause, then recreates playback on resume.
- Keeps audio muted by default.
- Packages with a generated `AppIcon.icns` stored under `Resources/`.

## Run

```sh
swift run WallpaperEngineMac
```

The app appears in the menu bar. Use `Import Folder or Video` to add local assets, then apply a supported video wallpaper from the menu or the library window.

## Automatic light/dark switching

In the menu bar app, open `Automation`:

- Use `Set Current as Light/Day` and `Set Current as Dark/Night`, or use the matching buttons in the library window.
- Pick `Follow System Appearance` to mirror macOS Light/Dark Mode.
- Pick `Follow Day/Night Schedule` to switch at the built-in 06:00 and 18:00 boundaries.

Bundled samples for quick local testing:

- `SampleWallpapers/ambient-test-loop`
- `SampleWallpapers/mixkit-abstract-macro-fluid-background`
- `SampleWallpapers/city-pop-a-long-vacation-upscaled-4k` (light/day)
- `SampleWallpapers/city-pop-dark-4k-aesthetic-city-night` (dark/night)

## Test

```sh
swift run WallpaperEngineSmokeTests
```

## Notes

This app does not download or redistribute Wallpaper Engine workshop content. It only plays assets the user has already obtained and imported locally.
