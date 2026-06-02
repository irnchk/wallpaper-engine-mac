<div align="center">

<img src="Resources/AppIcon.png" alt="WallpaperEngineMac 아이콘" width="128" height="128" />

# WallpaperEngineMac

**로컬에 보유한 Wallpaper Engine 스타일 동영상 배경화면을 재생하는 네이티브 macOS 메뉴바 앱.**

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![UI](https://img.shields.io/badge/menu%20bar-AppKit%20%2B%20AVFoundation-lightgrey)
![Status](https://img.shields.io/badge/status-MVP-success)

[English](README.md) · **한국어**

</div>

<p align="center">
  <img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="City Pop 라이브 배경화면 샘플" width="860" />
</p>

> 이미 보유한 배경화면 에셋을 데스크톱 아이콘 뒤에서 재생합니다 — 하드웨어 디코딩, 배터리 친화적, 기본 음소거.

---

## ✨ 주요 기능

- **Wallpaper Engine 구조 임포트** — `Steam/steamapps/workshop/content/431960/` 같은 워크샵 폴더, `project.json`이 들어 있는 개별 배경화면 폴더, 단일 `project.json`, 또는 직접 `.mp4` / `.m4v` / `.mov` 파일을 가져옵니다.
- **가벼운 라이브러리 창** — `project.json` 메타데이터를 파싱하고, 지원/미지원 프로젝트를 다운샘플된 미리보기 썸네일과 함께 목록으로 보여줍니다.
- **데스크톱 아이콘 뒤에서 재생** — 연결된 모든 디스플레이에서 `AVQueuePlayer` + `AVPlayerLooper`(VideoToolbox 하드웨어 디코딩)로 재생합니다.
- **자동 Light/Dark 전환** — Light/주간과 Dark/야간 배경화면을 따로 지정하고, macOS 외관 모드나 간단한 주야간 스케줄에 따라 자동 전환합니다.
- **배터리 우선 전력 관리** — 화면 잠금, 디스플레이 슬립, 저전력 모드, 배터리 사용(옵션), 사용자 일시정지, 또는 배경화면 창이 가려질 때 자동으로 멈춥니다.
- **디코더 자원 해제** — 장시간 일시정지 후 디코더 자원을 해제하고, 재개 시 재생을 다시 생성합니다.
- **기본 음소거** — 클릭 한 번으로 토글 가능.
- `Resources/`에 생성된 `AppIcon.icns` 포함.

---

## 🌗 자동 Light / Dark 전환

한 쌍을 지정해두면 시스템 외관 모드나 주야간 스케줄을 따라 전환됩니다.

<table>
  <tr>
    <th align="center">☀️ Light / 주간</th>
    <th align="center">🌙 Dark / 야간</th>
  </tr>
  <tr>
    <td><img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="Light/주간 배경화면" width="420" /></td>
    <td><img src="SampleWallpapers/city-pop-dark-4k-aesthetic-city-night/preview.jpg" alt="Dark/야간 배경화면" width="420" /></td>
  </tr>
  <tr>
    <td align="center"><code>city-pop-a-long-vacation-upscaled-4k</code></td>
    <td align="center"><code>city-pop-dark-4k-aesthetic-city-night</code></td>
  </tr>
</table>

메뉴바 앱에서 **`Automation`** 메뉴를 엽니다:

- **`Set Current as Light/Day`**, **`Set Current as Dark/Night`**를 사용하거나, 라이브러리 창의 해당 버튼을 사용합니다.
- **`Follow System Appearance`**를 선택하면 macOS Light/Dark 모드를 따라갑니다.
- **`Follow Day/Night Schedule`**를 선택하면 내장된 06:00 / 18:00 경계에서 전환됩니다.

---

## 🖼️ 동봉된 샘플 배경화면

빠른 로컬 테스트를 위해 Wallpaper Engine 스타일 동영상 프로젝트 형태로 구성되어 있어 바로 임포트할 수 있습니다.

<table>
  <tr>
    <td width="50%"><img src="SampleWallpapers/ambient-test-loop/preview.jpg" alt="앰비언트 테스트 루프" width="100%" /></td>
    <td width="50%"><img src="SampleWallpapers/mixkit-abstract-macro-fluid-background/preview.jpg" alt="추상 매크로 플루이드 배경" width="100%" /></td>
  </tr>
  <tr>
    <td align="center"><b>Ambient Test Loop</b><br/><code>SampleWallpapers/ambient-test-loop</code><br/><sub>4K · 10초 · 30 fps</sub></td>
    <td align="center"><b>Abstract Macro Fluid</b><br/><code>SampleWallpapers/mixkit-abstract-macro-fluid-background</code><br/><sub>1080p · 약 13초</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="시티팝 라이트" width="100%" /></td>
    <td width="50%"><img src="SampleWallpapers/city-pop-dark-4k-aesthetic-city-night/preview.jpg" alt="시티팝 다크" width="100%" /></td>
  </tr>
  <tr>
    <td align="center"><b>City Pop — A Long Vacation</b> ☀️<br/><code>city-pop-a-long-vacation-upscaled-4k</code><br/><sub>업스케일 4K · 60 fps</sub></td>
    <td align="center"><b>Aesthetic City at Night</b> 🌙<br/><code>city-pop-dark-4k-aesthetic-city-night</code><br/><sub>4K · 30 fps</sub></td>
  </tr>
</table>

---

## 🚀 실행

```sh
swift run WallpaperEngineMac
```

앱이 메뉴바에 나타납니다. **`Import Folder or Video`**로 로컬 에셋을 추가한 뒤, 메뉴나 라이브러리 창에서 지원되는 동영상 배경화면을 적용합니다.

## 🧪 테스트

```sh
swift run WallpaperEngineSmokeTests
```

---

## 📦 프로젝트 구조

```
WallpaperEngineMac/
├── Sources/
│   ├── WallpaperEngineCore/   # project.json 파싱, 라이브러리 스캔
│   ├── WallpaperEngineMac/    # 메뉴바 앱, 렌더러, 전력 관리자
│   └── WallpaperEngineSmokeTests/
├── SampleWallpapers/          # 임포트 가능한 샘플 동영상 프로젝트
├── Resources/                 # 앱 아이콘
└── Scripts/build-app.sh       # .app 번들 생성
```

---

## 🎬 크레딧 & 라이선스

각 샘플 폴더에는 전체 출처가 담긴 `SOURCE.md`가 포함되어 있습니다. 요약:

| 샘플 | 출처 | 라이선스 / 비고 |
| --- | --- | --- |
| Ambient Test Loop | Pixabay 4K 앰비언트 루프 | 로컬 테스트용 픽스처 |
| Abstract Macro Fluid | [Mixkit](https://mixkit.co/free-stock-video/abstract-macro-fluid-background-101740/) | [Mixkit Free License](https://mixkit.co/license/#videoFree) |
| City Pop — A Long Vacation | [DesktopHut](https://www.desktophut.com/City-Pop-A-Long-Vacation-Live-Wallpaper) | 개인 로컬 사용; 업스케일됨 |
| Aesthetic City at Night | [MotionBgs](https://motionbgs.com/aesthetic-city-at-the-night) | 권리는 원저작자에게 있음 |

이 앱은 Wallpaper Engine 워크샵 콘텐츠를 **다운로드하거나 재배포하지 않습니다.** 사용자가 이미 적법하게 확보하여 로컬로 임포트한 에셋만 재생합니다. 동봉된 샘플 배경화면은 로컬 테스트 용도로만 포함되어 있으며, 재사용 전 각 출처의 약관을 준수하세요.
