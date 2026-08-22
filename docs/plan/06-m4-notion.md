# 넵넵 개발 계획서 — 06. M4 Notion 내보내기 + 최소 서버 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [05-m3-summary](05-m3-summary.md)

**한 줄 요약:** Notion OAuth(토큰 교환용 최소 Vercel 서버 포함) → 대상 DB 선택 → 회의록 페이지 생성/갱신 → 자동 내보내기까지, 내보내기 시트(1g)를 Notion 경로로 완성한다. PRD F7. 이후 TestFlight 배포 시작점.

관련 문서: [00-overview](00-overview.md) · Google Docs는 [08-m5-gdocs-storage](08-m5-gdocs-storage.md)

## 디자인 참조

- 내보내기 시트(대상 선택 → 진행 → 완료)와 설정의 연동 행은 **와이어프레임 1g·1h 확정본** 기준. 착수 전 `/design-sync` 확인 (import 프롬프트는 00-overview §4).

## 목표

상세 화면에서 "내보내기" → Notion DB 선택 → 진행률 → "Notion에서 열기" 링크가 동작하고, 같은 회의를 다시 내보내면 기존 페이지가 갱신된다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `server/` (신규 Vercel 프로젝트) | 신설 | Hono + TypeScript |
| `server/src/index.ts` | 신설 | 라우팅 진입점 |
| `server/src/routes/notionOAuth.ts` | 신설 | `POST /v1/oauth/notion/exchange` |
| `server/.env` (Vercel env) | 신설 | `NOTION_CLIENT_ID/SECRET` |
| `Core/Export/NotionAuthService.swift` | 신설 | OAuth 플로우 (ASWebAuthenticationSession) |
| `Core/Export/NotionAPIClient.swift` | 신설 | search/DB 조회/페이지 생성·갱신 |
| `Core/Export/NotionBlockBuilder.swift` | 신설 | Summary+전사 → Notion 블록 변환 |
| `Core/Export/ExportService.swift` | 신설 | @Observable — 내보내기 상태 머신·자동 내보내기 |
| `Core/Export/KeychainStore.swift` | 신설 | 토큰 보관 |
| `Features/Export/ExportSheet.swift` | 신설 | 1g 시트 3단계 |
| `Features/Export/NotionTargetPicker.swift` | 신설 | DB 목록 피커 |
| `Features/Settings/SettingsView.swift` | 신설 | 1h 중 "연동" 섹션만 (나머지 M5·M6) |
| `NepNepTests/NotionBlockBuilderTests.swift` | 신설 | 블록 변환·분할 |

## 핵심 작업

### 1. 최소 서버 (Vercel + Hono)

```ts
// POST /v1/oauth/notion/exchange  { code, redirectUri } → { accessToken, workspaceName, botId }
app.post('/v1/oauth/notion/exchange', async (c) => {
  const { code, redirectUri } = await c.req.json()
  const basic = btoa(`${env.NOTION_CLIENT_ID}:${env.NOTION_CLIENT_SECRET}`)
  const r = await fetch('https://api.notion.com/v1/oauth/token', {
    method: 'POST',
    headers: { Authorization: `Basic ${basic}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ grant_type: 'authorization_code', code, redirect_uri: redirectUri }),
  })
  // 실패 시 상태코드 그대로 전달. 토큰은 저장하지 않고 반환만.
})
```

- 서버는 무상태: 토큰 저장·로깅 금지 (개인정보 문구와 일치해야 함). 배포: `vercel deploy` — M5에서 라우트가 늘어나므로 처음부터 `routes/` 분리.
- 클라이언트 secret이 앱에 들어가지 않는 것이 이 서버의 존재 이유 (연구 결과: Notion 공개 통합의 토큰 교환은 Basic 인증 필수).

### 2. NotionAuthService (F7-1)

- `ASWebAuthenticationSession`으로 Notion authorize URL 열기 (`owner=user`, redirect는 커스텀 스킴 `nepnep://oauth/notion`) → code 수신 → 서버 exchange → 토큰을 Keychain(`kSecAttrAccessibleAfterFirstUnlock`) 저장.
- Notion 토큰은 만료 없음(공개 통합) — 401 응답 시 연결 해제 상태로 전환하고 재연결 유도.

### 3. NotionAPIClient (연구 결과 반영)

- 공통 헤더: `Notion-Version: 2022-06-28` (data source 분리 이전 안정 버전 고정 — 2025-09-03 대응은 오픈 이슈로), `Authorization: Bearer`.
- `POST /v1/search` filter `{property: "object", value: "database"}` → DB 목록 (피커용, 최근 사용 DB는 UserDefaults).
- `POST /v1/pages`: parent database_id + properties(제목 프로퍼티는 `GET /v1/databases/{id}`로 스키마를 읽어 title 타입 프로퍼티 키를 찾는다 — "이름"/"Name" 하드코딩 금지) + children 블록.
- 갱신(재내보내기 — 1g 노트 4, 00-overview 확정 결정): `meeting.notionPageURL`에서 pageID 파싱 → 기존 자식 블록 전부 조회(`GET /v1/blocks/{id}/children` 페이지네이션) 후 삭제(`DELETE /v1/blocks/{id}`) → 새 블록 append. 페이지가 삭제됐으면(404) 새로 생성으로 폴백.
- 제한 준수: 요청당 블록 ≤100 → 초과분은 `PATCH /v1/blocks/{page}/children` 반복 append. rich_text 1건 ≤2,000자 → 초과 발화는 2,000자 단위 분할. 요청 간 350ms 대기(~3req/s). 429 시 `Retry-After` 존중 후 1회 재시도.

### 4. NotionBlockBuilder (유닛 테스트 대상)

- 구성: H1 제목 → 메타(callout: 날짜·길이·참석자) → H2 한 줄 요약 → H2 주요 논의(bulleted) → H2 결정사항 → H2 할 일(`to_do` 블록, `checked = todo.isDone` — F7 할 일 상태 동기화) → H2 전사(발화당 paragraph: **화자명 bold + [mm:ss]** + 본문).
- 테스트: 100블록 초과 분할 / 2,000자 초과 발화 분할 / 빈 요약(전사만) / to_do checked 매핑.

### 5. ExportSheet (1g) + ExportService

- 시트 3단계: 대상 선택(연결된 대상 1개면 프리셀렉트, 대상 행 탭 → NotionTargetPicker push) → 진행(단일 진행률 "블록 N / M 작성" + 취소) → 완료(페이지 링크 + "Notion에서 열기").
- 진행 중 시트를 내려도 백그라운드 계속(1g 노트 3) — ExportService가 Task 보유, 실패 시 같은 시트에 원인 한 줄 + "다시 시도".
- **자동 내보내기 토글**(1g·00-overview 확정): 켜면 이후 회의는 처리 완료 시 ExportService가 자동 실행, 시트 생략, 완료 알림에 링크. 설정 > 연동의 스위치와 동일 UserDefaults 키.
- 재내보내기 완료 화면에는 "기존 페이지를 갱신했어요" 한 줄 안내.

### 6. 설정 화면 — 연동 섹션 (1h 일부)

- 홈 상단 툴바 기어 → SettingsView. 이번 마일스톤에서는 "연동" 섹션만: Notion 행(연결 상태/DB명 우측 값, 탭 → 대상 변경·연결 해제 상세) + Google Docs 행(비활성 "연결 안 됨" — M5) + 자동 내보내기 스위치. 나머지 섹션은 자리 표시자 없이 생략(M5·M6에서 추가).

## 완료 기준

- [ ] `xcodebuild test`: NotionBlockBuilderTests ≥4케이스 통과
- [ ] 실기기: Notion 연결 → DB 선택 → 48분 실회의 내보내기 성공, Notion 앱에서 요약·할 일(체크 상태 포함)·전사 확인
- [ ] 같은 회의 재내보내기 → 새 페이지가 생기지 않고 기존 페이지 내용 갱신
- [ ] 150개 발화 이상 회의(블록 >100)가 분할 append로 완주
- [ ] 자동 내보내기 ON → 새 회의 처리 완료 시 시트 없이 Notion 페이지 생성 + 알림
- [ ] 연결 해제 → 재연결 정상, 서버 로그에 토큰 미기록 확인
- [ ] TestFlight 빌드 업로드 (PRD §11 M4 산출물)
