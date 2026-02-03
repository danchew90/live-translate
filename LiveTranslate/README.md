# Live Translate - iOS Real-time Video Translation

iOS 앱에서 재생되는 비디오의 음성을 실시간으로 인식하고 번역하여 자막으로 표시하는 앱입니다.

## 요구사항

- **iOS 18.0+** (Translation 프레임워크 필요)
- **Xcode 16+**
- **Swift 6.0+**

## 사용된 Apple 프레임워크

| 프레임워크 | 용도 |
|------------|------|
| `AVFoundation` / `AVKit` | 비디오 재생, 오디오 추출, PiP |
| `Speech` | 실시간 음성 인식 (STT) |
| `Translation` | 온디바이스 텍스트 번역 |
| `AVFAudio` | TTS (선택적) |
| `SwiftUI` | UI |

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    TranslationCoordinator                    │
│                    (메인 코디네이터)                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ VideoPlayer │───▶│   Audio     │───▶│   Speech    │     │
│  │   Module    │    │ Extraction  │    │ Recognition │     │
│  └─────────────┘    └─────────────┘    └──────┬──────┘     │
│                                               │             │
│                                               ▼             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │     TTS     │◀───│ Translation │◀───│  Subtitle   │     │
│  │   Module    │    │   Module    │    │  Timeline   │     │
│  └─────────────┘    └─────────────┘    └──────┬──────┘     │
│                                               │             │
│                                               ▼             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │     PiP     │    │  Subtitle   │    │  Subtitle   │     │
│  │   Module    │    │ Compositor  │    │  Overlay    │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 데이터 흐름

```
AVPlayer (비디오 재생)
       │
       ▼
MTAudioProcessingTap (오디오 추출)
       │
       ▼
PCM Audio Buffer (Mono, 16kHz)
       │
       ▼
SFSpeechAudioBufferRecognitionRequest (스트리밍 STT)
       │
       ▼
인식된 텍스트 (부분 + 최종)
       │
       ▼
TranslationSession (문장 단위 번역)
       │
       ▼
SubtitleTimeline (자막 타임라인)
       │
       ├──▶ SubtitleOverlayView (SwiftUI 오버레이)
       │
       └──▶ SubtitleCompositor (비디오 프레임 합성 - PiP용)
```

## 프로젝트 구조

```
LiveTranslate/
├── Sources/
│   ├── App/
│   │   ├── LiveTranslateApp.swift      # 앱 진입점
│   │   └── ContentView.swift           # 메인 뷰
│   │
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── SubtitleSegment.swift   # 자막 세그먼트 모델
│   │   │   └── AppConfiguration.swift  # 앱 설정
│   │   │
│   │   └── Services/
│   │       └── TranslationCoordinator.swift  # 메인 코디네이터
│   │
│   ├── Modules/
│   │   ├── AudioExtraction/
│   │   │   └── AudioExtractionModule.swift   # MTAudioProcessingTap
│   │   │
│   │   ├── SpeechRecognition/
│   │   │   └── SpeechRecognitionModule.swift # 스트리밍 STT
│   │   │
│   │   ├── Translation/
│   │   │   └── TranslationModule.swift       # Translation 프레임워크
│   │   │
│   │   ├── VideoPlayer/
│   │   │   └── VideoPlayerModule.swift       # AVPlayer 관리
│   │   │
│   │   ├── Subtitle/
│   │   │   ├── SubtitleCompositor.swift      # 비디오 합성
│   │   │   └── SubtitleOverlayView.swift     # SwiftUI 오버레이
│   │   │
│   │   ├── PictureInPicture/
│   │   │   └── PictureInPictureModule.swift  # PiP 관리
│   │   │
│   │   ├── TTS/
│   │   │   └── TextToSpeechModule.swift      # 음성 합성
│   │   │
│   │   └── Settings/
│   │       └── SettingsView.swift            # 설정 화면
│   │
│   └── Resources/
│       └── Info.plist
│
└── README.md
```

## 핵심 모듈 설명

### 1. AudioExtractionModule
`MTAudioProcessingTap`을 사용하여 AVPlayer에서 재생 중인 비디오의 오디오를 추출합니다.

```swift
// 오디오 믹스 생성
let audioMix = audioExtraction.createAudioMix(for: playerItem)
playerItem.audioMix = audioMix
```

**주요 기능:**
- 비디오 오디오 스트림에서 실시간 PCM 버퍼 추출
- 16kHz 모노 포맷으로 변환 (Speech 프레임워크 요구사항)
- 시스템 오디오 캡처 없이 인앱 비디오만 처리

### 2. SpeechRecognitionModule
`SFSpeechAudioBufferRecognitionRequest`를 사용한 스트리밍 음성 인식.

```swift
// 오디오 버퍼 추가
speechRecognition.appendAudioBuffer(buffer, at: time)
```

**주요 기능:**
- 실시간 부분 결과 지원
- 온디바이스 인식 (가능한 경우)
- 침묵 감지로 세그먼트 자동 분리
- 언어 자동 감지 또는 수동 선택

### 3. TranslationModule
iOS 18+ Translation 프레임워크를 사용한 온디바이스 번역.

```swift
// 번역 세션 구성
try await translation.configure(source: .english, target: .korean)

// 텍스트 번역
await translation.translate(text: "Hello", segmentId: uuid)
```

**주요 기능:**
- 문장 단위 번역 (단어 단위 X)
- 오프라인 번역 지원 (언어 모델 다운로드 시)
- 번역 요청 스로틀링

### 4. SubtitleCompositor
자막을 비디오 프레임에 합성하여 PiP에서도 표시.

**두 가지 접근 방식:**

1. **AVVideoComposition + CoreAnimation** (안정적)
   - 자막을 비디오 레이어에 합성
   - PiP, 화면 캡처에서 자막 표시됨
   - 정적 자막에 적합

2. **Custom AVVideoCompositor** (동적)
   - 실시간 자막 업데이트 가능
   - 프레임별 렌더링

### 5. PictureInPictureModule
`AVPictureInPictureController`를 사용한 PiP 관리.

```swift
// PiP 시작
pipModule.startPiP()
```

**주의사항:**
- PiP에서 자막이 보이려면 비디오 컴포지션에 자막이 포함되어야 함
- PiP 오버레이 해킹은 지양

## 스레딩 모델

```
Main Thread (UI)
├── SwiftUI Views
├── TranslationCoordinator
├── SpeechRecognitionModule (delegate callbacks)
└── TranslationModule

Background Threads
├── MTAudioProcessingTap callbacks (render thread)
├── AVAudioConverter
└── CIContext rendering
```

**중요:** `MTAudioProcessingTap` 콜백은 렌더 스레드에서 호출되므로, 메인 스레드 작업은 `DispatchQueue.main.async`로 전환해야 합니다.

## 성능 목표

| 단계 | 목표 지연시간 |
|------|--------------|
| STT | ~0.3–1.0초 |
| 번역 | ~0.2–1.0초 |
| 전체 | **1–3초** |

## 권한 요청

```xml
<!-- Info.plist -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>음성 인식으로 비디오 오디오를 텍스트로 변환합니다.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>번역할 비디오를 선택하기 위해 사진 라이브러리 접근이 필요합니다.</string>
```

## 빌드 및 실행

1. Xcode 16+에서 프로젝트 열기
2. 개발 팀 설정
3. iOS 18+ 디바이스 또는 시뮬레이터 선택
4. 빌드 및 실행

## 제한사항

- ❌ 서드파티 라이브러리 사용 안 함
- ❌ 외부 API/서버 사용 안 함
- ❌ 시스템 전체 오디오 캡처 안 함
- ❌ 다른 앱의 오디오 번역 안 함

## 라이선스

Private - All rights reserved
