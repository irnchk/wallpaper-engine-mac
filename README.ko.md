<div align="center">

<img src="Resources/AppIcon.png" alt="WallpaperEngineMac 아이콘" width="128" height="128" />

# WallpaperEngineMac

**내가 가진 Wallpaper Engine 스타일 동영상 배경화면을 macOS에서 재생하는 메뉴바 앱.**

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![UI](https://img.shields.io/badge/menu%20bar-AppKit%20%2B%20AVFoundation-lightgrey)
![Status](https://img.shields.io/badge/status-MVP-success)

[English](README.md) · **한국어**

</div>

<p align="center">
  <img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="City Pop 라이브 배경화면 샘플" width="860" />
</p>

> 이미 가지고 있는 영상 배경화면을 데스크톱 아이콘 뒤에서 틀어 줍니다. 하드웨어 디코딩으로 가볍게 돌아가고, 배터리를 아끼며, 소리는 기본적으로 꺼져 있습니다.

---

## ✨ 한눈에 보기

- **Wallpaper Engine 폴더를 그대로 가져오기** — `Steam/steamapps/workshop/content/431960/` 같은 워크샵 폴더는 물론, `project.json`이 든 배경화면 폴더, `project.json` 파일 하나, 또는 `.mp4` / `.m4v` / `.mov` 영상 파일을 바로 불러올 수 있습니다.
- **가벼운 라이브러리 창** — `project.json`을 읽어 제목·종류를 정리하고, 미리보기 썸네일과 함께 재생 가능 여부까지 한눈에 보여 줍니다.
- **아이콘 뒤에서 재생** — 연결된 모든 디스플레이에서 `AVQueuePlayer` + `AVPlayerLooper`로 끊김 없이 반복 재생합니다. 디코딩은 VideoToolbox가 하드웨어로 처리합니다.
- **라이트/다크 자동 전환** — 밝을 때와 어두울 때 쓸 배경화면을 따로 정해 두면, macOS 외관 모드나 시간대(주간/야간)에 맞춰 알아서 바꿔 줍니다.
- **배터리를 먼저 생각하는 절전** — 화면이 잠기거나, 디스플레이가 꺼지거나, 저전력 모드일 때, 배터리로 돌아갈 때(선택), 직접 멈췄을 때, 다른 창에 완전히 가려졌을 때 재생을 자동으로 멈춥니다.
- **오래 멈추면 디코더까지 정리** — 일정 시간 정지 상태가 이어지면 디코더 자원을 풀어 메모리를 돌려주고, 다시 켜질 때 재생을 새로 띄웁니다.
- **기본 음소거** — 필요하면 클릭 한 번으로 켜고 끌 수 있습니다.
- `Resources/`에 만들어 둔 `AppIcon.icns` 포함.

---

## 🌗 라이트 / 다크 자동 전환

한 쌍만 정해 두면 시스템 외관 모드나 시간대를 따라 알아서 바뀝니다.

<table>
  <tr>
    <th align="center">☀️ 라이트 / 주간</th>
    <th align="center">🌙 다크 / 야간</th>
  </tr>
  <tr>
    <td><img src="SampleWallpapers/city-pop-a-long-vacation-upscaled-4k/preview.jpg" alt="라이트/주간 배경화면" width="420" /></td>
    <td><img src="SampleWallpapers/city-pop-dark-4k-aesthetic-city-night/preview.jpg" alt="다크/야간 배경화면" width="420" /></td>
  </tr>
  <tr>
    <td align="center"><code>city-pop-a-long-vacation-upscaled-4k</code></td>
    <td align="center"><code>city-pop-dark-4k-aesthetic-city-night</code></td>
  </tr>
</table>

메뉴바 앱에서 **`Automation`** 메뉴를 열고:

- 지금 적용된 배경화면을 **`Set Current as Light/Day`** 또는 **`Set Current as Dark/Night`**로 지정합니다(라이브러리 창의 버튼으로도 가능).
- **`Follow System Appearance`** — macOS 라이트/다크 모드를 그대로 따라갑니다.
- **`Follow Day/Night Schedule`** — 06:00과 18:00을 기준으로 주간·야간을 바꿉니다.

---

## 🖼️ 함께 들어 있는 샘플 배경화면

바로 테스트해 볼 수 있도록 Wallpaper Engine 형식의 동영상 프로젝트로 만들어 두었습니다. 폴더째 가져오면 됩니다.

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
    <td align="center"><b>City Pop — A Long Vacation</b> ☀️<br/><code>city-pop-a-long-vacation-upscaled-4k</code><br/><sub>4K 업스케일 · 60 fps</sub></td>
    <td align="center"><b>Aesthetic City at Night</b> 🌙<br/><code>city-pop-dark-4k-aesthetic-city-night</code><br/><sub>4K · 30 fps</sub></td>
  </tr>
</table>

---

## 🚀 실행

```sh
swift run WallpaperEngineMac
```

실행하면 메뉴바에 앱이 뜹니다. **`Import Folder or Video`**로 로컬 파일을 추가한 다음, 메뉴나 라이브러리 창에서 원하는 영상 배경화면을 적용하세요.

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
│   ├── WallpaperEngineMac/    # 메뉴바 앱, 렌더러, 전력 관리
│   └── WallpaperEngineSmokeTests/
├── SampleWallpapers/          # 가져올 수 있는 샘플 동영상 프로젝트
├── Resources/                 # 앱 아이콘
└── Scripts/build-app.sh       # .app 번들 생성
```

---

## 🎬 출처 & 라이선스

샘플 폴더마다 자세한 출처를 담은 `SOURCE.md`가 들어 있습니다. 요약하면 다음과 같습니다.

| 샘플 | 출처 | 라이선스 / 비고 |
| --- | --- | --- |
| Ambient Test Loop | Pixabay 4K 앰비언트 루프 | 로컬 테스트용 |
| Abstract Macro Fluid | [Mixkit](https://mixkit.co/free-stock-video/abstract-macro-fluid-background-101740/) | [Mixkit Free License](https://mixkit.co/license/#videoFree) |
| City Pop — A Long Vacation | [DesktopHut](https://www.desktophut.com/City-Pop-A-Long-Vacation-Live-Wallpaper) | 개인 로컬 사용 · 업스케일본 |
| Aesthetic City at Night | [MotionBgs](https://motionbgs.com/aesthetic-city-at-the-night) | 권리는 원저작자에게 있음 |

이 앱은 Wallpaper Engine 워크샵 콘텐츠를 **내려받거나 재배포하지 않습니다.** 사용자가 이미 정당하게 확보해 로컬로 가져온 파일만 재생합니다. 함께 넣어 둔 샘플 배경화면은 로컬 테스트용이며, 다시 사용하기 전에 각 출처의 약관을 꼭 확인하세요.
