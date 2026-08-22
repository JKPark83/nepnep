# M0 테스트 세트

계획서 [01-m0-spike.md](../../docs/plan/01-m0-spike.md) §1 기준. PRD §2.3의 구성(2인/4인/6인 × 조용함/시끄러움 × 30분 내외, 최소 8개)을 채운다.

## 파일 규약

| 항목 | 규약 |
|---|---|
| 오디오 | `NN-<인원>p-<환경>.wav` — 예: `01-2p-quiet.wav` (16kHz mono WAV) |
| 정답 대본 | `NN-<이름>.ref.txt` — 사람이 교정한 전문 (문장부호 무관, CER 계산용) |
| 화자 라벨 | `NN-<이름>.ref.rttm` — RTTM 형식 (DER 계산용) |
| 클로바노트 결과 | `NN-<이름>.clova.txt` — 블라인드 비교용 |

포맷 변환:

```sh
afconvert -f WAVE -d LEI16@16000 -c 1 in.m4a out.wav
```

## 구성 체크리스트

- [ ] 01: 2인 · 조용함
- [ ] 02: 2인 · 시끄러움
- [ ] 03: 4인 · 조용함
- [ ] 04: 4인 · 시끄러움
- [ ] 05: 6인 · 조용함
- [ ] 06: 6인 · 시끄러움
- [ ] 07: 자유 (실제 회의)
- [ ] 08: 자유 (실제 회의)

오디오 파일은 용량·저작권 문제로 git에 커밋하지 않는다(`.gitignore` 처리). 대본·라벨 텍스트만 커밋.

## 평가 실행

앱에서 내보낸 `result-*.json`을 이 폴더에 모은 뒤:

```sh
python3 -m venv .venv && source .venv/bin/activate
pip install jiwer pyannote.metrics
python3 eval.py result-01-2p-quiet-speechtranscriber.json 01-2p-quiet.ref.txt 01-2p-quiet.ref.rttm
```
