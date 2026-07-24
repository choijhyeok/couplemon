# CoupleMon

서로의 Mac 화면에 캐릭터와 짧은 말풍선을 띄우는 커플용 macOS 앱입니다.

## 현재 구현

- 모든 Space에 표시되는 투명 플로팅 패널
- 도트 이미지 선택 및 로컬 저장
- Codex pet v1/v2 `pet.json` + `spritesheet.webp` 선택, 검증, idle 애니메이션 재생
- Supabase Realtime Broadcast를 통한 두 Mac 말풍선·이모지 동기화
- macOS 이모지 선택기와 120자 말풍선 입력
- 말풍선은 전송·수신 후 5초 뒤 자동으로 숨김
- 캐릭터 우하단 핸들을 드래그하거나 메뉴에서 크기 70~130% 조절
- 메뉴 막대에서 표시 전환, 캐릭터 초기화, 말풍선 삭제
- 외부 에셋 없는 기본 픽셀 하트

Supabase 설정 전에는 로컬로만 동작하고, 설정 후에는 같은 연결 코드의 상대 Mac으로 실시간 전달합니다.

## 두 Mac 실시간 연결

1. Supabase 무료 프로젝트를 만들고 Connect 화면에서 Project URL과 `sb_publishable_...` key를 복사합니다. 기존 프로젝트의 legacy `anon` key도 지원합니다.
2. 각 Mac에서 **실시간 연결 설정…**을 열어 같은 URL, key, 연결 코드를 입력합니다.
3. 한쪽에서 **연결 코드 복사** 후 상대에게 전달하면 편합니다.

별도 DB 테이블은 필요 없습니다. 메시지와 이모지는 Realtime Broadcast로 현재 접속한 상대에게만 전달되며 저장되지 않습니다. 연결 코드는 채널 주소 역할을 하므로 외부에 공개하지 마세요.

## Codex 애니메이션 펫

메뉴 막대의 **Codex 애니메이션 펫 선택…**에서 Codex가 만든 펫 폴더를 선택합니다. 선택 창은 기본적으로 `~/.codex/pets`에서 열립니다.

지원 규격:

- 버전 필드가 없는 v1 `1536×1872`, 또는 `spriteVersionNumber: 2`인 v2 `1536×2288`
- PNG 또는 WebP, `192×208` 셀
- idle 행 6프레임과 hatch-pet 표준 타이밍
- macOS 동작 줄이기 설정에서는 첫 프레임 고정

## 요구사항

- macOS 14 이상
- Swift 5.10 이상

## 실행

```bash
swift run CoupleMon
```

## 테스트

```bash
swift test
```

Xcode 없이 Command Line Tools만 설치된 환경에서는 XCTest를 찾지 못할 수 있습니다. 이 경우 핵심 입력 규칙을 직접 검사할 수 있습니다.

```bash
swiftc Sources/CoupleMon/MessageText.swift Sources/CoupleMon/RealtimeSettings.swift Sources/CoupleMon/HatchPetContract.swift Sources/CoupleMon/HatchPetPackage.swift Checks/main.swift -o .build/message-check
.build/message-check
```

## 앱 번들 생성

```bash
./Scripts/package-app.sh
open dist/CoupleMon.app
```

스크립트는 로컬 실행용 ad-hoc 서명을 사용합니다. 외부 배포 시 Developer ID 서명과 Apple 공증으로 교체해야 합니다.

## 설치 패키지 생성

```bash
./Scripts/package-installer.sh
```

생성된 `dist/CoupleMon.pkg`를 다른 Mac에서 열면 `/Applications/CoupleMon.app`에 설치됩니다. 현재 패키지는 개인 테스트용으로 서명·공증되지 않았으므로 macOS가 차단하면 Finder에서 패키지를 Control-클릭한 뒤 **열기**를 선택합니다. 경고 없이 배포하려면 Developer ID Installer 서명과 Apple 공증이 필요합니다.

## 다음 단계

1. 커플 초대 코드와 기기 등록
2. 잠자기/오프라인 복구
3. 로그인 시 자동 실행
4. Developer ID 배포 자동화
