"""맥에서 Whisper를 띄워 아이폰이 붙는 전사 서버.

앱이 여러 전사 서비스를 같은 코드로 부를 수 있게 OpenAI의
`POST /v1/audio/transcriptions` 형태를 그대로 흉내 낸다. 그래서 이 서버와
OpenAI·Groq처럼 같은 규격을 쓰는 유료 서비스가 앱 입장에서는 주소만 다른
같은 엔진이 된다.

`condition_on_previous_text`는 기본으로 끈다. 켜 두면 긴 한국어 회의에서
같은 문장을 수십 번 반복하며 무너지는 일이 재현됐고, 끄니 반복이 사라지면서
속도까지 33% 빨라졌다 (M4 맥미니, 48.6분 회의 기준 2분 39초).
"""

import asyncio
import json
import os
import tempfile
import time
from typing import Any

import mlx_whisper
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import StreamingResponse
from starlette.concurrency import run_in_threadpool

# 전사가 도는 동안 연결을 살려 두려고 흘려 보내는 바이트.
# 공백이라 JSON 파서가 그냥 건너뛴다.
HEARTBEAT = b" "
HEARTBEAT_SECONDS = 3

MODEL_PATH = os.environ.get(
    "NEPNEP_WHISPER_MODEL",
    os.path.expanduser("~/.cache/nepnep-whisper/whisper-large-v3-turbo"),
)
MODEL_NAME = os.environ.get("NEPNEP_WHISPER_MODEL_NAME", "whisper-large-v3-turbo")

app = FastAPI(title="NepNep Whisper Server")


@app.get("/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "model": MODEL_NAME, "model_path": MODEL_PATH}


@app.get("/v1/models")
def models() -> dict[str, Any]:
    return {
        "object": "list",
        "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "local"}],
    }


@app.post("/v1/audio/transcriptions")
async def transcriptions(
    file: UploadFile = File(...),
    model: str = Form(MODEL_NAME),
    language: str | None = Form(None),
    prompt: str | None = Form(None),
    response_format: str = Form("json"),
    temperature: float = Form(0.0),
    # OpenAI는 `timestamp_granularities[]`로 배열을 받는다. 여기서는 쓰이는 값이
    # 하나뿐이라 문자열로 받고 word가 들어 있으면 단어 타임스탬프를 켠다.
    # 대괄호가 붙은 이름이 정식이고 넵넵 앱도 그쪽으로 보내지만, curl로 손으로
    # 찔러 볼 때는 대괄호 없이 쓰게 되므로 둘 다 받는다.
    timestamp_granularities: str = Form("segment"),
    timestamp_granularities_bracket: str = Form("", alias="timestamp_granularities[]"),
):
    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    want_words = "word" in (timestamp_granularities + timestamp_granularities_bracket)

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    started = time.monotonic()
    size_mb = os.path.getsize(tmp_path) / 1_048_576
    # 끝나야 로그가 찍히면 도는 중인지 죽은 건지 알 수가 없다. 시작도 찍는다.
    print(f"[transcribe] 시작 — {file.filename} · {size_mb:.1f}MB", flush=True)

    # 전사는 몇 분씩 걸리는 블로킹 호출이다. 스레드풀로 넘겨야 그동안 이벤트
    # 루프가 살아 있어 다른 연결을 돌볼 수 있다.
    job = asyncio.create_task(
        run_in_threadpool(
            lambda: mlx_whisper.transcribe(
                tmp_path,
                path_or_hf_repo=MODEL_PATH,
                language=language,
                initial_prompt=prompt,
                temperature=temperature,
                word_timestamps=want_words,
                condition_on_previous_text=False,
                verbose=None,
            )
        )
    )

    def build_body() -> str:
        result = job.result()
        elapsed = time.monotonic() - started
        segments = result.get("segments", [])
        duration = segments[-1]["end"] if segments else 0.0
        print(
            f"[transcribe] 끝 — {file.filename} · 오디오 {duration:.0f}초 · "
            f"처리 {elapsed:.1f}초 ({duration / elapsed if elapsed else 0:.0f}배속) · "
            f"구간 {len(segments)}개",
            flush=True,
        )

        text = result.get("text", "").strip()
        if response_format == "text":
            return text
        if response_format != "verbose_json":
            return json.dumps({"text": text}, ensure_ascii=False)

        payload: dict[str, Any] = {
            "task": "transcribe",
            "language": result.get("language", language or ""),
            "duration": duration,
            "text": text,
            "segments": segments,
        }
        if want_words:
            # OpenAI는 단어를 구간 안이 아니라 최상위 배열로 준다. 앱이 그쪽을 읽는다.
            payload["words"] = [w for seg in segments for w in seg.get("words", [])]
        return json.dumps(payload, ensure_ascii=False)

    # 48분짜리면 4분을 기다리는데, 그동안 한 바이트도 안 흐르면 아이폰이 연결을
    # 놓아 버린다("The network connection was lost"). 도는 동안 공백을 흘려 보내
    # 연결을 살아 있게 만든다 — JSON은 앞에 붙은 공백을 무시하므로 파서는 그대로다.
    async def stream():
        try:
            while not job.done():
                yield HEARTBEAT
                await asyncio.sleep(HEARTBEAT_SECONDS)
            yield build_body().encode()
        except Exception as exc:  # 업로드가 오디오가 아니거나 디코딩이 실패한 경우
            print(f"[transcribe] 실패 — {file.filename} · {exc}", flush=True)
            yield json.dumps({"error": {"message": str(exc)}}, ensure_ascii=False).encode()
        finally:
            os.unlink(tmp_path)

    media_type = "text/plain" if response_format == "text" else "application/json"
    return StreamingResponse(stream(), media_type=media_type)
