# 전사 서버

맥에서 Whisper를 띄워 아이폰이 붙는다. 앱이 OpenAI·Groq 같은 유료 서비스와
같은 코드로 부를 수 있게 `POST /v1/audio/transcriptions` 규격을 흉내 낸다.

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
- 전사가 도는 동안 3초마다 공백 한 바이트를 흘려 보낸다. 몇 분간 아무것도 안
  보내면 아이폰이 연결을 놓아 버린다("The network connection was lost").
- 모델 경로와 이름은 `NEPNEP_WHISPER_MODEL`·`NEPNEP_WHISPER_MODEL_NAME`으로
  바꿀 수 있다.
