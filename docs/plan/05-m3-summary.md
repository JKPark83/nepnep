# 넵넵 개발 계획서 — 05. M3 요약 생성 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [04-m2-transcript-ui](04-m2-transcript-ui.md)

**한 줄 요약:** Foundation Models(온디바이스)로 4종 템플릿 요약을 map-reduce 방식으로 생성하고, 상세 화면 요약 탭(1e)을 실데이터로 완성한다. PRD F6 · F5의 요약 관련 잔여분.

관련 문서: [00-overview](00-overview.md) · [PRD F6](../PRD.md)

## 디자인 참조

- 요약 탭 레이아웃·템플릿 칩·할 일 체크박스는 **와이어프레임 1e 확정본** 기준. 착수 전 `/design-sync`로 최신본 확인 (import 프롬프트는 00-overview §4).

## 목표

48분 회의의 전사에서 "한 줄 요약 / 주요 논의 / 결정사항 / 할 일(담당자·기한)"이 생성되어 상세 화면에 표시되고, 템플릿을 바꾸면 기기 안에서 재요약된다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `Core/Summary/SummaryService.swift` | 신설 | map-reduce 오케스트레이션 |
| `Core/Summary/SummarySchemas.swift` | 신설 | `@Generable` 출력 스키마 |
| `Core/Summary/SummaryTemplates.swift` | 신설 | 템플릿 4종 프롬프트·섹션 정의 |
| `Core/Summary/TranscriptChunker.swift` | 신설 | 토큰 한도 내 청크 분할 |
| `Core/Models/Summary.swift` | 재활용·수정 | 필드 확장 (M1 스텁 → 전체) |
| `Core/Pipeline/ProcessingCoordinator.swift` | 재활용·수정 | summarizing 단계 연결 + 체크포인트 stage 추가 |
| `Features/MeetingDetail/SummaryTabView.swift` | 신설 | 스켈레톤 → 실데이터 (1e) |
| `Features/MeetingDetail/TodoRowView.swift` | 신설 | 할 일 체크박스 행 |
| `NepNepTests/TranscriptChunkerTests.swift` | 신설 | 분할 경계 케이스 |
| `NepNepTests/SummaryTemplateTests.swift` | 신설 | 템플릿→프롬프트 조립 |

## 핵심 작업

### 1. Summary 모델 확장

```swift
@Model final class Summary {
    var templateTypeRaw: String          // general/oneOnOne/interview/standup
    var oneLiner: String                 // 한 줄 요약 (홈 카드에도 사용)
    var sectionsData: Data               // [SummarySection] JSON — 템플릿별 가변 섹션
    var generatedAt: Date
    @Relationship(deleteRule: .cascade) var todos: [TodoItem]
}
@Model final class TodoItem {
    var text: String; var assignee: String?; var due: String?   // 자유 텍스트 기한 ("8월 26일")
    var isDone: Bool; var orderIndex: Int
}
struct SummarySection: Codable { let title: String; let bullets: [String] }
```

- 홈 카드의 "한 줄 요약"(04에서 첫 발화로 대체했던 부분)을 `summary.oneLiner`로 교체.

### 2. @Generable 스키마 (SummarySchemas)

```swift
import FoundationModels

@Generable struct ChunkDigest {
    @Guide(description: "이 구간의 핵심 논의 3~5개, 한국어 한 문장씩") var points: [String]
    @Guide(description: "구간에서 결정된 사항") var decisions: [String]
    @Guide(description: "할 일. '내용|담당자|기한' 형태, 담당자·기한을 모르면 빈칸") var actionItems: [String]
}
@Generable struct FinalSummary {
    @Guide(description: "회의 전체 한 줄 요약, 60자 이내") var oneLiner: String
    @Guide(description: "주요 논의 불릿 3~6개") var keyPoints: [String]
    @Guide(description: "결정사항 불릿") var decisions: [String]
    @Guide(description: "할 일 '내용|담당자|기한'") var actionItems: [String]
}
```

- 템플릿별 차이는 최종 단계 instructions에서만: 1on1(합의·피드백 중심), 인터뷰(질문·답변 요지·평가 메모), 스탠드업(어제/오늘/블로커) — 섹션 제목 매핑은 `SummaryTemplates`의 상수 테이블.

### 3. TranscriptChunker — 4,096 토큰 한도 대응 (연구 결과: instructions+prompt+출력 합산 한도)

- 전략: 발화를 순서대로 담되 **청크당 한국어 약 1,200자**(≈ 안전 마진 포함 프롬프트 예산) 이하로 분할. 발화 중간은 자르지 않는다. iOS 26.4+에서는 `tokenCount(for:)`가 있으면 이를 사용해 검증하고, 없으면 문자수 휴리스틱을 사용한다.
- 테스트: 경계에서 발화 미절단 / 초장문 단일 발화(>한도)는 문장 단위로 강제 분할 / 빈 전사 → 빈 결과.

### 4. SummaryService — map-reduce

```
[Utterance…] → Chunker → chunk별 LanguageModelSession(ChunkDigest)   // map (순차 실행 — 발열 고려)
             → digests 텍스트 병합 → 새 세션(FinalSummary, 템플릿 instructions)  // reduce
             → digests 병합본조차 한도 초과 시 digest들을 다시 chunk하여 2단 reduce
```

- 세션은 청크마다 새로 생성(컨텍스트 누적 방지). `exceededContextWindowSize` 잡으면 해당 청크를 반으로 재분할해 재시도.
- `SystemLanguageModel.default.availability`가 `.available`이 아니면: summarizing 단계를 건너뛰고 Meeting에 `summaryUnavailable` 플래그 → 요약 탭에 사유 안내(기기 미지원/모델 다운로드 필요). 처리 전체를 실패로 만들지 않는다.
- `actionItems` 문자열 파싱: `"내용|담당자|기한"` split → TodoItem. 파이프 없으면 전체를 text로.
- ProcessingCoordinator: merging 뒤 summarizing 단계 추가, 진행률 = 처리한 청크 수/전체, 체크포인트에 `digests.json` 추가. 백그라운드에서는 스트리밍 미사용(연구 결과 권고)이므로 청크 단위 일괄 응답.

### 5. 요약 탭 UI (1e)

- 상단 템플릿 칩(현재 템플릿 표시) → 탭하면 4종 선택 메뉴 → 변경 시 **기기 안 재요약**(reduce 단계만 재실행 — digests 체크포인트가 있으면 map 생략, 없으면 전체 재실행) + 진행 중 스켈레톤. `meeting.typeRaw`도 함께 갱신.
- 섹션 렌더링: 한 줄 요약 카드 → 주요 논의 불릿 → 결정사항 → 할 일("N / M 완료" 헤더 + 체크박스 행: 내용·담당자·기한). 체크 토글은 `todo.isDone` 즉시 저장 (내보내기 동기화는 M4).
- 04에서 자리만 둔 "할 일로 추가"(전사 발화 길게 누르기) 활성화: 발화 텍스트로 TodoItem append.

## 완료 기준

- [ ] `xcodebuild test`: TranscriptChunkerTests ≥4케이스 · SummaryTemplateTests ≥4케이스(템플릿별 instructions 조립) 통과
- [ ] 실기기: 30분 이상 실회의 처리 → 요약 탭에 4개 섹션 표시, 할 일에 담당자·기한 최소 1건 파싱됨
- [ ] 템플릿 변경(일반→스탠드업) → 재요약 완료 후 섹션 구성이 바뀜, `xcrun simctl`이 아닌 실기기에서 소요 시간 기록
- [ ] Foundation Models 비가용 시뮬레이션(availability 스텁) → 요약 없이 처리 완료 + 요약 탭 안내 문구
- [ ] 홈 카드 한 줄 요약이 `summary.oneLiner`로 표시됨
- [ ] 처리 중 화면(1d) 3단계에 "요약 중" 진행률 표시
