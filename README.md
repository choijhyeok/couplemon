# CoupleMon

서로의 Mac 화면에 캐릭터와 짧은 말풍선을 띄우는 커플용 macOS 앱입니다.

## 현재 구현

- 모든 Space에 표시되는 투명 플로팅 패널
- 도트 이미지 선택 및 로컬 저장
- 120자 말풍선 입력 및 표시
- 메뉴 막대에서 표시 전환, 캐릭터 초기화, 말풍선 삭제
- 외부 에셋 없는 기본 픽셀 하트

현재 메시지는 로컬 메모리에만 표시되고 디스크에 저장되지 않습니다. 상대 Mac과 동기화하는 실시간 전송은 다음 단계입니다.

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
swiftc Sources/CoupleMon/MessageText.swift Checks/main.swift -o .build/message-check
.build/message-check
```

## 앱 번들 생성

```bash
./Scripts/package-app.sh
open dist/CoupleMon.app
```

스크립트는 로컬 실행용 ad-hoc 서명을 사용합니다. 외부 배포 시 Developer ID 서명과 Apple 공증으로 교체해야 합니다.

## 다음 단계

1. 커플 초대 코드와 기기 등록
2. WebSocket 메시지 전송 및 재접속 동기화
3. 잠자기/오프라인 복구
4. 로그인 시 자동 실행
5. Developer ID 배포 자동화
