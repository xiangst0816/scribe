<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · **한국어**

**Fn을 누른 채 말하고, 손을 떼세요. 지금 커서가 있는 곳에 바로 텍스트가 들어갑니다.**

macOS 메뉴 막대에 상주하는 로컬 음성 입력 도구입니다. [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)을 사용하며, 음성 인식은 사용자의 Mac에서 처리됩니다. 기본 설정에서는 오디오를 클라우드로 보내지 않습니다.

[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe는 무엇인가요

Scribe는 작지만 자주 거슬리는 문제를 해결합니다. 코드를 쓰거나, 메시지에 답하거나, 메모를 하다가 잠깐 음성으로 입력하고 싶을 때가 있습니다. 하지만 앱을 바꾸고 싶지 않고, 시스템 받아쓰기를 켜고 싶지도 않고, 클라우드 문자 변환을 기다리고 싶지도 않을 때가 있죠.

Scribe는 메뉴 막대에 머뭅니다. **Fn**을 누른 채 말하고 손을 떼면, 인식된 텍스트가 현재 포커스된 입력 위치에 자동으로 붙여 넣어집니다. Safari, VS Code, Slack, 메모, 웹 입력란, 터미널에서 그대로 사용할 수 있습니다.

음성 인식은 CoreML용으로 변환된 OpenAI Whisper 모델로 로컬에서 실행됩니다. 모델을 한 번 다운로드한 뒤에는 일반적인 받아쓰기에 네트워크 연결이 필요 없고, 오디오도 Mac 밖으로 나가지 않습니다.

## 주요 기능

- **어디서든 푸시투토크**: `Fn`을 누르면 녹음하고, 손을 떼면 텍스트로 변환해 커서 위치에 붙여 넣습니다.
- **로컬 Whisper 인식**: 빠름, 균형, 고품질 세 가지 모드를 제공합니다. 각각 `openai_whisper-base`, `openai_whisper-small_216MB`, `openai_whisper-large-v3-v20240930_626MB`에 대응하며, 모델은 한 번만 다운로드됩니다.
- **바로 사용할 수 있는 대체 인식**: Whisper 모델을 다운로드하거나 로드하는 동안에는 Apple Speech를 사용합니다.
- **다국어 지원**: 영어, 중국어(간체/번체), 일본어, 한국어를 지원합니다. Whisper가 언어를 자동으로 판단할 수 있고, 짧은 발화에서는 메뉴에서 언어를 고정할 수도 있습니다.
- **녹음 상태 표시**: 녹음 중에는 화면 하단에 작은 오버레이가 나타나 실시간 음량을 보여 줍니다.
- **CJK 입력 환경 고려**: 붙여 넣기 전에 잠시 ASCII 입력 소스로 전환해, 한중일 IME가 `⌘V`를 가로채는 일을 피합니다.
- **메뉴 막대 전용**: Dock 아이콘도, 메인 창도 없습니다.
- **작은 앱 본체**: 바이너리는 약 5 MB입니다. Whisper 모델은 Application Support 아래에 따로 저장됩니다.

## 요구 사항

- macOS 14.0 Sonoma 이상
- Apple Silicon Mac 권장. Whisper는 CoreML을 통해 Neural Engine을 사용합니다
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

1. `Scribe.app`을 엽니다. 실행되면 메뉴 막대에 펜촉 아이콘이 나타납니다.
2. macOS 안내에 따라 **마이크**, **음성 인식**, **손쉬운 사용** 권한을 허용합니다.
   - 손쉬운 사용 권한은 `Fn` 키를 전역으로 감지하고, 인식 결과를 다른 앱에 붙여 넣는 데 사용됩니다.
3. 기본값인 “균형” 모델이 백그라운드에서 다운로드됩니다. 크기는 약 210 MB이며, 진행률은 메뉴 막대 아이콘에 표시됩니다.
4. 다운로드가 끝나면 메뉴 상단에 **균형 · 사용 중** 이라고 표시됩니다. 이후에는 로컬 Whisper로 인식합니다.

모델을 다운로드하는 중에도 Scribe를 사용할 수 있습니다. 이때는 임시로 Apple Speech를 사용합니다.

## 사용법

| 동작 | 결과 |
|---|---|
| `Fn` 누르고 있기 | 녹음을 시작하고, 화면 하단에 음량 오버레이를 표시합니다. |
| `Fn`에서 손 떼기 | 녹음을 끝낸 뒤 잠시 후 현재 커서 위치에 텍스트를 붙여 넣습니다. |
| 메뉴 막대 → **음성 품질** | 빠름, 균형, 고품질을 전환합니다. 아직 없는 모델은 필요할 때 다운로드됩니다. |
| 메뉴 막대 → **언어** | 언어를 자동으로 판단하거나, 특정 언어로 고정합니다. |
| 메뉴 막대 → **사용** | 앱을 종료하지 않고 전역 `Fn` 감지를 잠시 켜거나 끕니다. |

### 단축키

현재 핫키는 **Fn**으로 고정되어 있습니다. 다른 수정자 키로 바꾸고 싶다면 [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift)에서 시작하면 됩니다. PR도 환영합니다.

### 로컬에 저장되는 파일

| 경로 | 내용 |
|---|---|
| `~/Library/Application Support/Scribe/Models/<variant>/` | 다운로드된 CoreML 모델 |
| `~/Library/Logs/Scribe.log` | 애플리케이션 로그 |
| `~/Library/Preferences/com.yetone.Scribe.plist` | 언어와 음성 품질 같은 UserDefaults |

## 개인정보 보호

- 모델 다운로드가 끝난 뒤에는 음성 인식 자체가 네트워크 요청을 보내지 않습니다.
- 일반적인 사용 중 오디오는 한 번의 키 입력 동안만 메모리에 보관되고, 문자 변환이 끝나면 폐기됩니다.
- 네트워크가 필요한 경우는 주로 두 가지입니다. 처음 선택한 Whisper 모델을 Hugging Face에서 다운로드할 때, 그리고 예전 LLM 다듬기 경로를 직접 다시 켜서 OpenAI 호환 API를 호출할 때입니다. 후자는 기본적으로 꺼져 있고 메뉴에도 표시되지 않습니다.

## 저장소 구조

이 저장소에는 macOS 앱과 공식 사이트가 함께 들어 있습니다. 두 부분은 서로 독립적입니다.

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/Scribe/                ← Swift 앱 소스 코드
├── web/                           ← Astro 기반 공식 사이트. Cloudflare Pages에 배포
└── .github/workflows/
    └── deploy-web.yml             ← web/ 변경 시에만 공식 사이트 배포
```

앱과 공식 사이트는 빌드 의존성을 공유하지 않습니다. 사이트 개발, 빌드, Cloudflare 설정은 [web/README.md](web/README.md)를 참고하세요.

## 앱 구조

```text
Scribe.app
├── KeyMonitor          ── CGEventTap으로 .flagsChanged를 감시해 Fn 상태를 가져옴
├── SpeechProvider      ── 인식 엔진 프로토콜. start/stop/cancel과 콜백을 정의
│   ├── AppleSpeechProvider    ── SFSpeechRecognizer 기반 대체 인식
│   └── WhisperSpeechProvider  ── WhisperKit + AudioProcessor 기반 로컬 인식
├── ModelManager        ── 모델 모드, 다운로드 진행률, CoreML 로드와 사전 준비
├── OverlayPanel        ── 보더리스 NSPanel. 녹음 오버레이와 파형 애니메이션 담당
├── TextInjector        ── 클립보드 + ⌘V로 텍스트를 삽입하고 입력 소스 전환 처리
└── AppDelegate         ── 메뉴 막대 UI, 상태 아이콘, 인식 엔진 선택
```

앱 전체는 약 1,500줄의 Swift로 되어 있습니다. Xcode 프로젝트는 없고, [Package.swift](Package.swift)와 작은 [Makefile](Makefile)만으로 `swift build`, `.app` 생성, ad-hoc 서명을 묶어 처리합니다.

## 감사의 말

- [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift): OpenAI Whisper를 Swift + CoreML에서 사용할 수 있게 해 주는 WhisperKit.
- [OpenAI Whisper](https://github.com/openai/whisper): 음성 인식 모델.

## 라이선스

[MIT](LICENSE) © Scribe contributors.
