<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · **한국어**

**Fn을 누른 채 말하고, 손을 떼세요. 지금 커서가 있는 곳에 바로 텍스트가 들어갑니다.**

macOS 메뉴 막대에 상주하는 가벼운 푸시투토크 음성 입력 도구입니다. macOS에 내장된 음성 인식을 사용하므로 모델을 따로 받지 않으며, 별도 창도 띄우지 않습니다.

[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe는 무엇인가요

Scribe는 작지만 자주 거슬리는 문제를 해결합니다. 코드를 쓰거나, 메시지에 답하거나, 메모를 하다가 잠깐 음성으로 입력하고 싶을 때가 있습니다. 하지만 앱을 바꾸고 싶지 않고, 시스템 받아쓰기를 켜고 싶지도 않고, 클라우드 문자 변환을 기다리고 싶지도 않을 때가 있죠.

Scribe는 메뉴 막대에 머뭅니다. **Fn**을 누른 채 말하고 손을 떼면, 인식된 텍스트가 현재 포커스된 입력 위치에 자동으로 붙여 넣어집니다. Safari, VS Code, Slack, 메모, 웹 입력란, 터미널에서 그대로 사용할 수 있습니다.

음성 인식은 macOS에 내장된 `SFSpeechRecognizer`를 사용합니다. Apple Silicon Mac에서 Sonoma 이상을 사용하는 경우 주요 언어는 보통 온디바이스로 처리됩니다. 그 외의 조건에서는 Apple의 음성 인식 개인정보 보호 정책에 따라 오디오가 Apple 서버로 전송될 수 있습니다.

## 주요 기능

- **어디서든 푸시투토크**: `Fn`을 누르면 녹음하고, 손을 떼면 텍스트로 변환해 커서 위치에 붙여 넣습니다.
- **실시간 자막 알약**: 녹음 중 음량 캡슐 위에 반투명 알약이 떠올라 지금 말하고 있는 한 문장을 실시간으로 보여 줍니다. 손을 떼기 전에 인식 결과를 미리 확인할 수 있습니다.
- **꼬리 버퍼**: `Fn`에서 손을 뗀 뒤에도 약 500밀리초 동안 녹음이 이어집니다. 문장 끝을 조금 늦게 말해도 잘리지 않습니다. 버퍼 동안 다시 `Fn`을 누르면 같은 녹음이 끊김 없이 이어집니다.
- **다국어 지원**: 영어, 중국어(간체/번체), 일본어, 한국어를 지원합니다. 메뉴에서 언어를 고정하거나, 시스템 설정을 따르도록 둘 수 있습니다.
- **CJK 입력 환경 고려**: 붙여 넣기 전에 잠시 ASCII 입력 소스로 전환해, 한중일 IME가 `⌘V`를 가로채는 일을 피합니다.
- **메뉴 막대 전용**: Dock 아이콘도, 메인 창도 없습니다.

## 요구 사항

- macOS 14.0 Sonoma 이상
- macOS 음성 인식이 지원하는 언어(영어, 중국어, 일본어, 한국어는 기본 제공)
- Xcode Command Line Tools

명령줄 도구가 없다면 다음 명령으로 설치할 수 있습니다.

```bash
xcode-select --install
```

## 소스에서 설치

```bash
git clone https://github.com/xiangst0816/scribe.git
cd scribe
make install        # 빌드한 뒤 /Applications/Scribe.app 으로 복사
```

설치하지 않고 빌드하거나 디버깅만 하려면:

```bash
make build          # ./Scribe.app 생성
make run            # 빌드 후 실행
make clean          # 빌드 산출물 삭제
```

## 처음 실행할 때

1. `Scribe.app`을 엽니다. 실행되면 메뉴 막대에 Scribe 아이콘이 나타납니다.
2. macOS 안내에 따라 **마이크**, **음성 인식**, **손쉬운 사용** 권한을 허용합니다.
   - 손쉬운 사용 권한은 `Fn` 키를 전역으로 감지하고, 인식 결과를 다른 앱에 붙여 넣는 데 사용됩니다.
3. 다운로드해야 하는 모델은 없습니다. 권한 허용이 끝나면 바로 `Fn`을 눌러 사용할 수 있습니다.

## 사용법

| 동작 | 결과 |
|---|---|
| `Fn` 누르고 있기 | 녹음을 시작합니다. 화면 하단에 음량 캡슐이 나타나고, 그 위 알약이 지금 말하는 한 문장을 실시간으로 보여 줍니다. |
| `Fn`에서 손 떼기 | 약 500밀리초의 꼬리 버퍼 후 녹음을 종료하고, 현재 커서 위치에 텍스트를 붙여 넣습니다. |
| 메뉴 막대 → **언어** | 인식 언어를 고정하거나, 시스템 설정을 따라 자동 선택합니다. |
| 메뉴 막대 → **사용** | 앱을 종료하지 않고 전역 `Fn` 감지를 잠시 켜거나 끕니다. |

### 단축키

현재 핫키는 **Fn**으로 고정되어 있습니다. 다른 수정자 키로 바꾸고 싶다면 [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift)에서 시작하면 됩니다. PR도 환영합니다.

### 로컬에 저장되는 파일

| 경로 | 내용 |
|---|---|
| `~/Library/Logs/Scribe.log` | 애플리케이션 로그 |
| `~/Library/Preferences/com.yetone.Scribe.plist` | 선택한 언어 같은 UserDefaults |

## 개인정보 보호

- 음성 인식은 Apple 내장 `SFSpeechRecognizer`를 사용합니다. Apple Silicon Mac에서 Sonoma 이상을 쓸 때 주요 4개 언어는 보통 온디바이스로 처리됩니다. 그 외 조건에서는 Apple의 [음성 인식 개인정보 보호 정책](https://www.apple.com/legal/privacy/data/ko/speech-recognition/)에 따라 오디오가 Apple 서버로 전송될 수 있습니다.
- Scribe 자체는 그 외의 외부 네트워크 요청을 보내지 않습니다. 예외로 기본값으로 꺼져 있는 LLM 다듬기 경로를 직접 다시 켰을 때만 OpenAI 호환 API를 호출하며, 메뉴에는 표시되지 않습니다.
- 오디오는 한 번의 키 입력 동안(500밀리초 꼬리 버퍼 포함)만 메모리에 보관되고, 문자 변환이 끝나면 폐기됩니다.

## 저장소 구조

이 저장소에는 macOS 앱과 공식 사이트가 함께 들어 있습니다. 두 부분은 서로 독립적입니다.

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/
│   ├── Scribe/                    ← ScribeCore 라이브러리. 앱 로직 전부
│   └── ScribeApp/main.swift       ← NSApplication만 띄우는 얇은 실행 파일
├── Tests/ScribeCoreTests/         ← XCTest 단위 테스트
├── web/                           ← Astro 기반 공식 사이트. Cloudflare Pages에 배포
└── .github/workflows/
    └── deploy-web.yml             ← web/ 변경 시에만 공식 사이트 배포
```

앱과 공식 사이트는 빌드 의존성을 공유하지 않습니다. 사이트 개발, 빌드, Cloudflare 설정은 [web/README.md](web/README.md)를 참고하세요.

## 앱 구조

```text
Scribe.app
├── KeyMonitor             ── CGEventTap으로 .flagsChanged를 감시해 Fn 상태를 가져옴
├── SpeechProvider         ── 인식 엔진 프로토콜. start/stop/cancel과 onAudioLevel/onPartialResult/onFinalResult 콜백 정의
│   └── AppleSpeechProvider    ── SFSpeechRecognizer 기반 스트리밍 인식. 음량 미터 포함
├── OverlayPanel           ── 보더리스 NSPanel. 음량 캡슐과 그 위에 떠 있는 실시간 자막 알약 담당
├── TextInjector           ── 클립보드 + ⌘V로 텍스트를 삽입하고 입력 소스 전환 처리
└── AppDelegate            ── 메뉴 막대 UI, 상태 아이콘, 녹음 수명 주기
```

앱 전체는 수백 줄의 Swift로 되어 있고 `ScribeCore` 라이브러리와 얇은 실행 파일로 나뉘어 있습니다. Xcode 프로젝트는 없고, [Package.swift](Package.swift)와 작은 [Makefile](Makefile)만으로 `swift build`, `.app` 생성, ad-hoc 서명을 묶어 처리합니다. 테스트는 `swift test`로 실행합니다.

## 감사의 말

- [Sparkle](https://sparkle-project.org): 자동 업데이트 프레임워크.
- Apple [Speech](https://developer.apple.com/documentation/speech) 프레임워크: 인식 코어.

## 라이선스

[MIT](LICENSE) © Scribe contributors.
