# 넵넵 개발 계획서 — 08. M5-B Google Docs + 저장 공간 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [06-m4-notion](06-m4-notion.md) · [07-m5-server-iap](07-m5-server-iap.md)와 병행 가능

**한 줄 요약:** Google Docs 내보내기(OAuth·문서 생성·갱신)와 저장 공간 관리("오디오만 삭제" 포함)를 완성해 설정 화면(1h)의 남은 섹션을 채운다. PRD F7(Google 경로) · F11.

관련 문서: [00-overview](00-overview.md) · Notion 공통 구조는 [06-m4-notion](06-m4-notion.md)

## 디자인 참조

- 내보내기 시트의 Google 행(1g), 설정의 저장 공간·기본값 섹션(1h)은 와이어프레임 확정본 기준. 착수 전 `/design-sync` 확인 (import 프롬프트는 00-overview §4).

## 목표

Google 계정 연결 후 회의록이 지정 Drive 폴더에 Google Docs 문서로 생성·갱신되고, 설정에서 전체 사용량 확인과 "오디오만 삭제"가 동작한다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `server/src/routes/googleOAuth.ts` | 신설 | `POST /v1/oauth/google/exchange` · `POST /v1/oauth/google/refresh` |
| `Core/Export/GoogleAuthService.swift` | 신설 | OAuth (scope: `documents`, `drive.file`) + 토큰 갱신 |
| `Core/Export/GoogleDocsClient.swift` | 신설 | 문서 생성·batchUpdate·폴더 이동 |
| `Core/Export/GoogleDocsRequestBuilder.swift` | 신설 | Summary+전사 → batchUpdate 요청 변환 |
| `Core/Export/ExportService.swift` | 재활용·수정 | 대상 2종(Notion/Google) 분기 |
| `Features/Export/ExportSheet.swift` | 재활용·수정 | Google 행 활성화 + 폴더 피커 |
| `Features/Export/GoogleFolderPicker.swift` | 신설 | Drive 폴더 목록 피커 |
| `Features/Settings/StorageSection.swift` | 신설 | 저장 공간 섹션 (1h) |
| `Features/Settings/SettingsView.swift` | 재활용·수정 | Google 연동 행 + 저장 공간·기본값 섹션 |
| `NepNepTests/GoogleDocsRequestBuilderTests.swift` | 신설 | 요청 변환 |
| `NepNepTests/StorageCalcTests.swift` | 신설 | 용량 집계 |

## 핵심 작업

### 1. Google OAuth (F7-1)

- 서버 exchange: Google도 클라이언트 secret이 필요한 웹 클라이언트 대신 **iOS 클라이언트 ID + PKCE**를 사용하면 secret 없이 앱 단독 교환이 가능하다. 따라서 **기본 구현은 앱 내 PKCE 직교환**(`ASWebAuthenticationSession` + `https://oauth2.googleapis.com/token`)으로 하고, 서버 라우트는 만들지 않는다. (06의 Notion과 다른 점 — Notion은 PKCE 미지원이라 서버 필수.) 서버 라우트 산출물 행은 이 결정으로 **삭제 가능** — 착수 시점에 Google 정책이 바뀌었으면 06과 동일 패턴으로 추가.
- scope 최소화: `https://www.googleapis.com/auth/documents` + `https://www.googleapis.com/auth/drive.file` (drive.file은 앱이 만든 파일만 접근 — 심사·보안상 유리).
- refresh token을 Keychain 보관, access token 만료(3600s) 시 자동 갱신. 갱신 실패(revoked) → 연결 해제 상태 전환.

### 2. GoogleDocsClient + RequestBuilder (F7-3)

- 생성: `POST https://docs.googleapis.com/v1/documents` {title: "회의 제목 — M/d"} → documentId → `PATCH https://www.googleapis.com/drive/v3/files/{id}?addParents={folderId}`로 지정 폴더 이동.
- 본문 작성: `POST /v1/documents/{id}:batchUpdate` — `insertText` + `updateParagraphStyle`(HEADING_1·2) + `createParagraphBullets` 요청 시퀀스. **인덱스는 뒤에서 앞으로 삽입하면 재계산이 필요 없다** — RequestBuilder는 섹션을 역순으로 조립.
- 구성은 Notion과 동일 순서(제목→메타→요약→논의→결정→할 일(체크박스 `BULLET_CHECKBOX`)→전사). 공통 중간 표현을 만들지 말 것 — 빌더 2개가 각자 Summary/Utterance를 직접 읽는 편이 단순(코딩 가이드라인: 단일 사용 추상화 금지).
- 갱신(재내보내기): 문서 전체 범위 `deleteContentRange`(1 ~ endIndex-1) 후 재삽입. 404/403(삭제·권한 상실) 시 새 문서 생성 폴백.
- 폴더 피커: `GET drive/v3/files?q=mimeType='application/vnd.google-apps.folder' and trashed=false` — 이름 검색 + 최근 사용 기억.

### 3. ExportService 통합 (1g)

- 내보내기 시트에서 Notion·Google 중 선택(둘 다 연결 시 마지막 사용 대상 기억). 자동 내보내기는 연결된 모든 대상에 순차 실행 (PRD F7-5의 "동시 내보내기"는 순차 실행으로 충족 — 실패는 대상별 독립 표시).
- `meeting.googleDocURL` 저장 → 완료 화면 "Docs에서 열기".

### 4. 저장 공간 (F11, 1h)

- `StorageSection`: 전체 사용량 = 오디오(`Documents/audio` 재귀 합) + 전사·요약(SwiftData 스토어 파일 크기). 게이지 + 두 줄 내역.
- **"오디오만 삭제"**: 확인 알럿("회의록은 유지됩니다. 발화 재생은 더 이상 할 수 없어요") → 완료된 회의의 `recording.m4a` 전부 삭제 + `audioFileName = nil` → 전사 탭 재생 비활성(04에서 이미 처리). 처리 중·녹음됨 상태의 오디오는 제외.
- 회의별 삭제는 홈 스와이프(04)로 이미 존재 — 여기서는 전역 동작만.
- `StorageCalcTests`: 디렉터리 합산 / 오디오만 삭제 후 잔여 계산 (임시 디렉터리 픽스처).

### 5. 설정 기본값 섹션 (1h)

- 기본 회의 유형(4종 피커 — 녹음 시작 시 초기값), 처리 완료 알림 토글(끄면 NotificationService 발송 생략), 개인정보 처리방침 링크, 버전 표시. (전사 엔진 섹션은 M6에서 ModelAssetManager UI와 함께.)

## 완료 기준

- [ ] 실기기: Google 연결 → 폴더 선택 → 내보내기 → Docs 앱에서 제목·요약·체크박스 할 일·전사 확인
- [ ] 재내보내기 → 같은 문서가 갱신됨(문서 URL 불변)
- [ ] Notion·Google 둘 다 연결 + 자동 내보내기 ON → 처리 완료 시 두 대상 모두 생성
- [ ] "오디오만 삭제" → 전체 사용량의 오디오 항목 ≈0, 회의록 열람·검색 정상, 발화 탭 재생 비활성
- [ ] access token 강제 만료(1시간 경과) 후 내보내기 → 자동 갱신으로 성공
- [ ] `xcodebuild test`: GoogleDocsRequestBuilderTests ≥3 · StorageCalcTests ≥2 통과
