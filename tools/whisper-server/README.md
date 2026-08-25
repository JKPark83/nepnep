# 전사 서버

맥에서 Whisper를 띄워 아이폰이 붙는다. 앱이 OpenAI·Groq 같은 유료 서비스와
같은 코드로 부를 수 있게 `POST /v1/audio/transcriptions` 규격을 흉내 낸다.

## 길이 둘이다

| | 쓰는 곳 |
|---|---|
| `POST /v1/audio/transcriptions` | curl로 찔러 보거나 다른 클라이언트가 붙을 때. 한 연결로 결과까지 기다린다. |
| `POST /v1/jobs` → `GET /v1/jobs/<id>` | 넵넵 앱. 맡겨 두고 3초마다 찾아간다. |

앱이 뒤쪽을 쓰는 이유는 iOS가 백그라운드로 내려간 앱을 재우면서 소켓을 끊기
때문이다. 긴 회의를 맡기고 홈 버튼을 누르면 돌아왔을 때 `-1005`가 떴다.
맡겨 두면 요청 하나가 몇 초짜리라 그럴 일이 없고, 앱이 아예 죽었다 켜져도
서버가 결과를 한 시간 동안 들고 있다.

```bash
ID=$(curl -s -X POST http://<주소>:8927/v1/jobs \
  -F "file=@meeting.m4a" -F "language=ko" \
  -F "response_format=verbose_json" -F "timestamp_granularities[]=word" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
curl -s http://<주소>:8927/v1/jobs/$ID   # {"status":"running","elapsed":12.5}
```

끝나면 `{"status":"done", ...전사 결과}` — 결과를 감싸지 않고 그대로 펼쳐
주므로 동기 응답을 읽던 파서를 그대로 쓸 수 있다. 실패는
`{"status":"failed","error":{"message":...}}`, 없거나 만료된 id는 404다.

## 처음 한 번

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/huggingface-cli download mlx-community/whisper-large-v3-turbo \
  --local-dir ~/.cache/nepnep-whisper/whisper-large-v3-turbo
```

## 띄우기

```bash
./run.sh              # 테일스케일 주소:8927 — 공용 네트워크에는 안 뜬다
HOST=0.0.0.0 ./run.sh # 로컬 네트워크에도 열기
```

살아 있는지는 `curl http://<주소>:8927/health`로 본다.

## 아이폰에서 붙기

`ios/NepNep/Resources/engines.yml`의 `macmini` 항목 `baseURL`을 이 맥의 주소로
맞추고, 앱 설정 > 전사 엔진에서 고른다. 주소만 바뀌었다면 앱을 다시 빌드하는
대신 파일 앱의 넵넵 폴더에 있는 `engines.yml`을 고쳐도 된다.

## 알아 둘 것

- `condition_on_previous_text`는 꺼 둔다. 켜면 긴 한국어 회의에서 같은 문장을
  수십 번 반복하며 무너졌고, 끄니 반복이 사라지면서 속도까지 33% 빨라졌다
  (M4 맥미니, 48.6분 회의 2분 39초).
- 동기 경로는 전사가 도는 동안 3초마다 공백 한 바이트를 흘려 보낸다. 몇 분간
  아무것도 안 보내면 중간 장비가 연결을 끊는다. 대신 한번 흘려보내기 시작하면
  상태 코드로 실패를 알릴 수 없어, 오류도 본문에 `{"error":{...}}`로 실어 준다.
- 끝난 작업은 한 시간 뒤에 버린다(`JOB_TTL_SECONDS`). 서버를 다시 띄우면 맡긴
  것이 전부 사라지므로, 앱은 404를 받으면 실패로 본다.
- 모델 경로와 이름은 `NEPNEP_WHISPER_MODEL`·`NEPNEP_WHISPER_MODEL_NAME`으로
  바꿀 수 있다.
