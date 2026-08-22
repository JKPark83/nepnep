# 넵넵 개발 계획서 — 04. M2-B 홈·처리·전사 UI (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [03-m2-pipeline](03-m2-pipeline.md)

**한 줄 요약:** 홈(1b) · 처리 중(1d) · 회의록 상세의 전사 탭(1e) · 화자 이름 지정 시트(1f)를 와이어프레임 확정본대로 구현해, "녹음 → 처리 → 전사 확인 → 화자 이름 지정"의 앱 내 루프를 완성한다. PRD F4 · F5(요약 제외) · F10-4.

관련 문서: [00-overview](00-overview.md) · 요약 탭은 [05-m3-summary](05-m3-summary.md)

## 디자인 참조

- 이 문서의 모든 화면은 **와이어프레임 1b·1d·1e·1f 확정본**이 기준이다. 각 화면 구현 착수 전 `/design-sync`로 최신본을 다시 확인할 것 (import 프롬프트는 00-overview §4).
- 색·간격·라디우스는 `DesignTokens.swift`(M1 산출물)만 사용. 하드코딩 금지.

## 목표

실기기에서 녹음을 마치면: 처리 화면이 3단계 진행을 보여주고, 홈 카드가 진행률을 이어받고, 완료 후 상세 화면에서 화자별 전사를 읽고 화자 이름을 지정하고 합칠 수 있다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `Features/Home/HomeView.swift` | 신설 | 목록 + 검색 + 녹음 FAB (1b) |
| `Features/Home/MeetingCardView.swift` | 신설 | 상태별 카드 4종 |
| `Features/Home/MeetingStore.swift` | 신설 | @Observable — 목록 쿼리·검색·삭제 |
| `Features/Processing/ProcessingView.swift` | 신설 | 3단계 진행 화면 (1d) |
| `Features/MeetingDetail/MeetingDetailView.swift` | 신설 | 헤더 + 요약/전사 탭 컨테이너 (1e — 요약 탭은 M3 전까지 스켈레톤) |
| `Features/MeetingDetail/TranscriptListView.swift` | 신설 | 화자별 발화 리스트 + 구간 재생 |
| `Features/MeetingDetail/SpeakerNamingSheet.swift` | 신설 | 화자 이름 지정·합치기 시트 (1f) |
| `Features/MeetingDetail/AudioPlayerController.swift` | 신설 | AVAudioPlayer 래퍼 — 구간 재생 |
| `AppRootView.swift` | 재활용·수정 | 임시 버튼 제거 → NavigationStack(HomeView) + 딥링크 라우팅 |
| `NepNepTests/SpeakerMergeTests.swift` | 신설 | 화자 합치기 로직 |

## 핵심 작업

### 1. 홈 (1b — F4)

- `NavigationStack` + `List` 없이 `ScrollView + LazyVStack` 카드 레이아웃 (카드 16pt 라디우스, 카드 간 12pt). `.searchable`로 검색 — **제목 + 전사 본문** 대상(F4-4): `#Predicate`로 `title.localizedStandardContains(q) || utterances.contains { $0.text.localizedStandardContains(q) }`. 성능 문제가 보이면 오픈 이슈 E(FTS)로 이관.
- 카드 상태 4종 (1b 확정): 처리 중(진행 바 하단 노출, `processingProgress` 반영) / 완료(한 줄 요약 — M3 전까지 첫 발화 미리보기로 대체) / 실패("다시 정리하기" 버튼 1개 → `ProcessingCoordinator.enqueue` 재시도) / 녹음됨(복구된 녹음).
- 녹음 FAB: 68pt 원형, 스크롤 무관 하단 고정, 뒤에 배경 그라데이션. **길게 누르면 회의 유형 선택 메뉴**(contextMenu 아님 — `Menu` + 커스텀 프라이머리 액션). 탭 → RecordingView 풀스크린 커버.
- 빈 상태: 검색바 숨김("첫 회의를 녹음해 보세요" 카피 그대로), FAB 위 안내 한 줄.
- 카드 좌측 스와이프: 삭제(확인 알럿 — Meeting cascade + 오디오 디렉터리 삭제) / 제목 변경(알럿 TextField).
- 복구 배너: M1의 "복구된 녹음" Meeting이 있으면 목록 상단에 안내 배너 1회 노출.

### 2. 처리 중 화면 (1d — F10-4)

- 녹음 완료 직후 RecordingView가 이 화면으로 전환. 3단계 리스트: 전사 → 화자 구분 → 요약(M3 전까지 "대기" 고정 표시).
- **완료 단계는 체크로 접히고, 현재 단계 하나만 진행률 + 보조 설명**(예: "4명의 목소리를 찾았어요" — DiarizationService 결과의 화자 수). 스피너는 화면에 1개 이하.
- "홈으로" → dismiss, 홈 카드가 진행률 이어받음 (동일한 `meeting.processingProgress` 관찰이므로 별도 작업 없음).
- "전사본 먼저 보기": `processingStage`가 전사 완료 이후면 활성화 → 상세 화면 push (요약 영역은 스켈레톤).
- 실패 시: 이 화면을 원인 한 줄 + "다시 시도" 버튼으로 교체 (실패 원인 enum → 사용자 문구 매핑 테이블을 `ProcessingFailureReason+Message.swift`에).

### 3. 회의록 상세 — 컨테이너 + 전사 탭 (1e)

- 헤더: 제목(large title, 스크롤 시 내비게이션 바 축약 — 기본 동작) / 날짜·길이·유형 메타 라인 / 참석자 아바타 스택(화자 이름 첫 글자, `colorIndex` 배경) + 이름 나열.
- 탭: 요약 | 전사 세그먼트. M2-B에서는 요약 탭에 스켈레톤 뷰(placeholder 3블록 + "요약 준비 중")를 두고 M3에서 교체.
- 전사 탭(`TranscriptListView`): 발화 = 아바타 + 이름 + `mm:ss` 타임스탬프 + 본문. `LazyVStack` + `orderIndex` 정렬.
- **발화 탭 → 해당 구간부터 재생**: `AudioPlayerController.play(from: utterance.startTime)` — `recording.m4a` 로드, 재생 중 말풍선 accent 톤 + 인라인 재생바(1e 노트 6). 다른 발화 탭 시 기존 재생 중지. 오디오 파일이 없으면(오디오만 삭제 후) 탭 비활성.
- 발화 길게 누르기: 복사 / "할 일로 추가"(M3 Summary 필요 — M2-B에서는 복사만, 메뉴에 비활성 항목으로 자리만).
- 하단 고정 바: [전사|요약 전환은 상단 세그먼트] + "화자 이름 지정" / "내보내기"(M4 전까지 비활성 + "준비 중") 버튼 — 반투명 배경 + 상단 구분선.

### 4. 화자 이름 지정 시트 (1f — F5-2·3)

- `presentationDetents([.fraction(0.75), .large])`. 이름 TextField 포커스 시 `.large`로 승격.
- 화자 카드: 번호 + 이름 TextField("이름 입력" placeholder, 기존 `customName` 프리필) + 발화 횟수 + **대표 발화 3개(해당 화자의 가장 긴 발화 상위 3개, 시간순 표시)** + 각 발화 재생 버튼(동시 재생 1개 제한).
- 저장: `speaker.customName` 갱신 → 전사·요약·아바타 즉시 반영 (Utterance는 speakerID 참조이므로 자동).
- **합치기**: "같은 사람으로 합치기" 탭 → 선택 모드(카드에 선택 원형) → 2명 이상 선택 시 하단 버튼 "N명 합치기" → 실행: 선택 화자 중 첫 번째로 나머지의 Utterance `speakerID` 재지정 + Speaker 삭제. **되돌리기**: 실행 전 매핑 `[utteranceID: oldSpeakerID]`를 시트 세션 메모리에 보관, 스낵바 "합쳤어요 — 되돌리기" 5초.
- 딥링크: 처리 완료 알림 userInfo에 `showSpeakerNaming: true`를 넣어 상세 진입 시 시트 자동 표시 (1f 노트 4).
- 테스트(`SpeakerMergeTests`): 합치기 후 Utterance 재지정·Speaker 수 감소 / 되돌리기 후 원상복구 / 대표 발화 선정(최장 3개).

## 완료 기준

- [ ] `xcodebuild test`: SpeakerMergeTests ≥3케이스 포함 전체 통과
- [ ] 실기기 E2E: 녹음 10분 → 처리 화면 3단계 진행 → "홈으로" → 홈 카드 진행률 → 완료 후 카드 탭 → 전사 탭에서 발화 확인
- [ ] 발화 탭 → 해당 구간 재생 + accent 하이라이트, 다른 발화 탭 시 이전 재생 중지
- [ ] 화자 이름 지정: 이름 저장 후 전사·아바타 반영, 2명 합치기 → 되돌리기 정상
- [ ] 검색: 전사 본문에만 있는 단어로 홈 검색 시 해당 회의 노출
- [ ] 실패 카드 "다시 정리하기" → 재처리 완주
- [ ] 각 화면이 와이어프레임 1b·1d·1e·1f와 육안 대조로 일치 (다크 모드 포함)
