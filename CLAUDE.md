# CLAUDE.md - AI Assistant Guide for Live Translate

iOS 실시간 비디오 번역 앱 개발 가이드

## Project Overview

**Repository:** live-translate
**Platform:** iOS 18+
**Language:** Swift 6.0
**Status:** Core implementation complete

앱 내에서 재생되는 비디오의 음성을 실시간으로 인식하고 번역하여 자막으로 표시하는 iOS 앱입니다.

### 핵심 제약사항

- ❌ 서드파티 라이브러리 사용 금지
- ❌ 외부 API/서버 사용 금지
- ❌ Python 사용 금지
- ❌ 시스템 전체 오디오 캡처 금지 (인앱 비디오만)

---

## Quick Start

```bash
# Xcode 16+에서 프로젝트 열기
open LiveTranslate.xcodeproj

# 또는 Swift Package로 빌드
cd LiveTranslate
swift build
```

---

## Project Structure

```
live-translate/
├── CLAUDE.md                    # AI 어시스턴트 가이드 (이 파일)
├── README.md                    # 상세 기술 문서
├── Resources/
│   └── Info.plist
├── Sources/
│   ├── App/
│   │   ├── LiveTranslateApp.swift    # 앱 진입점
│   │   └── ContentView.swift         # 메인 UI
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── SubtitleSegment.swift # 자막 세그먼트 모델
│   │   │   └── AppConfiguration.swift # 앱 설정
│   │   └── Services/
│   │       └── TranslationCoordinator.swift # 메인 코디네이터
│   └── Modules/
│       ├── AudioExtraction/
│       │   └── AudioExtractionModule.swift   # MTAudioProcessingTap
│       ├── SpeechRecognition/
│       │   └── SpeechRecognitionModule.swift # 스트리밍 STT
│       ├── Translation/
│       │   └── TranslationModule.swift       # Translation 프레임워크
│       ├── VideoPlayer/
│       │   └── VideoPlayerModule.swift       # AVPlayer 관리
│       ├── Subtitle/
│       │   ├── SubtitleCompositor.swift      # 비디오 합성
│       │   └── SubtitleOverlayView.swift     # SwiftUI 오버레이
│       ├── PictureInPicture/
│       │   └── PictureInPictureModule.swift  # PiP 관리
│       ├── TTS/
│       │   └── TextToSpeechModule.swift      # 음성 합성
│       └── Settings/
│           └── SettingsView.swift            # 설정 화면
```

---

## Apple Frameworks Used

| 프레임워크 | 용도 |
|------------|------|
| `AVFoundation` / `AVKit` | 비디오 재생, 오디오 추출, PiP |
| `Speech` | 실시간 음성 인식 (STT) |
| `Translation` | 온디바이스 텍스트 번역 (iOS 18+) |
| `AVFAudio` | TTS (선택적) |
| `SwiftUI` | UI |

---

## Architecture

### 데이터 흐름 파이프라인

```
AVPlayer (비디오)
    ↓
MTAudioProcessingTap (오디오 추출)
    ↓
PCM Audio Buffer (Mono, 16kHz)
    ↓
SFSpeechAudioBufferRecognitionRequest (스트리밍 STT)
    ↓
인식된 텍스트 (부분 + 최종)
    ↓
TranslationSession (문장 단위 번역)
    ↓
SubtitleTimeline (자막 타임라인)
    ↓
화면 자막 + PiP 자막
```

### 핵심 모듈

1. **TranslationCoordinator**: 모든 모듈을 조율하는 메인 코디네이터
2. **AudioExtractionModule**: MTAudioProcessingTap으로 비디오 오디오 추출
3. **SpeechRecognitionModule**: 스트리밍 음성 인식
4. **TranslationModule**: iOS 18 Translation 프레임워크 래퍼
5. **SubtitleTimeline**: 자막 세그먼트 관리
6. **SubtitleCompositor**: 비디오 프레임에 자막 합성 (PiP용)
7. **PictureInPictureModule**: PiP 관리

---

## Key Implementation Details

### MTAudioProcessingTap (오디오 추출)

```swift
// AudioExtractionModule.swift:50-80
var callbacks = MTAudioProcessingTapCallbacks(
    version: kMTAudioProcessingTapCallbacksVersion_0,
    clientInfo: context,
    init: tapInit,
    finalize: tapFinalize,
    prepare: tapPrepare,
    unprepare: tapUnprepare,
    process: tapProcess  // 여기서 오디오 버퍼 추출
)

MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                           kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
```

### 스트리밍 STT

```swift
// SpeechRecognitionModule.swift:85-100
let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true  // 부분 결과 활성화
request.addsPunctuation = true

recognitionTask = recognizer.recognitionTask(with: request) { result, error in
    // 실시간 결과 처리
}
```

### Translation 프레임워크

```swift
// TranslationModule.swift:70-85
let configuration = TranslationSession.Configuration(
    source: sourceLanguage,  // nil = 자동 감지
    target: targetLanguage
)
translationSession = try await TranslationSession(configuration: configuration)
let response = try await session.translate(text)
```

---

## Development Guidelines

### Code Style

- Swift 6.0 concurrency (async/await, @MainActor)
- 모든 UI 코드는 `@MainActor`
- `nonisolated` 함수에서 MainActor 코드 호출 시 `Task { @MainActor in ... }`
- 명명 규칙:
  - `camelCase`: 변수, 함수
  - `PascalCase`: 타입, 프로토콜
  - `UPPER_SNAKE_CASE`: 상수

### Threading Model

```
Main Thread (@MainActor)
├── SwiftUI Views
├── TranslationCoordinator
├── ObservableObject 프로퍼티 업데이트

Background Threads
├── MTAudioProcessingTap 콜백 (렌더 스레드)
├── AVAudioConverter
└── CIContext 렌더링
```

### Performance Targets

| 단계 | 목표 지연시간 |
|------|--------------|
| STT | ~0.3–1.0초 |
| 번역 | ~0.2–1.0초 |
| **전체** | **1–3초** |

---

## AI Assistant Guidelines

### Do

- 코드 수정 전 기존 코드 먼저 읽기
- Apple 프레임워크만 사용
- Swift concurrency 패턴 준수 (@MainActor, async/await)
- 에러 처리 적절히 구현
- 스레드 안전성 고려

### Don't

- 서드파티 라이브러리 추가 ❌
- 외부 API 호출 ❌
- 시스템 오디오 캡처 시도 ❌
- ReplayKit 사용 ❌
- 과도한 엔지니어링 ❌

### Critical Files

| 파일 | 중요도 | 설명 |
|------|--------|------|
| `TranslationCoordinator.swift` | ⭐⭐⭐ | 핵심 조율 로직 |
| `AudioExtractionModule.swift` | ⭐⭐⭐ | MTAudioProcessingTap 구현 |
| `SpeechRecognitionModule.swift` | ⭐⭐⭐ | 스트리밍 STT |
| `TranslationModule.swift` | ⭐⭐ | Translation 프레임워크 래퍼 |
| `SubtitleCompositor.swift` | ⭐⭐ | PiP 자막 합성 |

---

## Troubleshooting

| 문제 | 해결 |
|------|------|
| PiP에서 자막 안 보임 | SubtitleCompositor로 비디오에 자막 합성 필요 |
| STT 권한 오류 | Info.plist에 NSSpeechRecognitionUsageDescription 확인 |
| Translation 실패 | iOS 18+ 확인, 언어 모델 다운로드 상태 확인 |
| 오디오 추출 안됨 | playerItem.audioMix 설정 확인 |

---

## Changelog

### 2026-02-03 - Core Implementation
- 전체 모듈 구조 구현
- MTAudioProcessingTap 오디오 추출
- 스트리밍 음성 인식
- Translation 프레임워크 통합
- SwiftUI 메인 UI
- PiP 지원
- TTS 지원

### Initial Setup (2026-02-03)
- 프로젝트 초기화
- CLAUDE.md 생성

---

*이 문서는 live-translate 코드베이스 작업 시 AI 어시스턴트를 위한 가이드입니다.*
