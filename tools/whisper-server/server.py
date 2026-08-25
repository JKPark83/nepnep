"""맥에서 Whisper를 띄워 아이폰이 붙는 전사 서버.

앱이 여러 전사 서비스를 같은 코드로 부를 수 있게 OpenAI의
`POST /v1/audio/transcriptions` 형태를 그대로 흉내 낸다. 그래서 이 서버와
OpenAI·Groq처럼 같은 규격을 쓰는 유료 서비스가 앱 입장에서는 주소만 다른
같은 엔진이 된다.

여기에 더해 `POST /v1/jobs`로 맡기고 `GET /v1/jobs/<id>`로 찾아가는 길을
따로 낸다. 긴 회의는 전사에 몇 분이 걸리는데, 그동안 연결 하나를 붙들고
있으면 아이폰이 백그라운드로 내려가는 순간 iOS가 앱을 재우면서 소켓이
끊긴다. 결과를 서버가 들고 있다가 앱이 돌아와서 물어보면 건네주는 편이 낫다.

`condition_on_previous_text`는 기본으로 끈다. 켜 두면 긴 한국어 회의에서
같은 문장을 수십 번 반복하며 무너지는 일이 재현됐고, 끄니 반복이 사라지면서
속도까지 33% 빨라졌다 (M4 맥미니, 48.6분 회의 기준 2분 39초).
"""

import asyncio
import json
import os
import tempfile
import time
import uuid
from typing import Any

import mlx_whisper
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from starlette.concurrency import run_in_threadpool

# 전사가 도는 동안 연결을 살려 두려고 흘려 보내는 바이트.
# 공백이라 JSON 파서가 그냥 건너뛴다.
HEARTBEAT = b" "
HEARTBEAT_SECONDS = 3

# 끝난 작업을 붙들어 두는 시간. 아이폰이 백그라운드에 있는 동안 결과를 여기
# 들고 있다가 돌아오면 건네준다.
JOB_TTL_SECONDS = 3600

MODEL_PATH = os.environ.get(
    "NEPNEP_WHISPER_MODEL",
    os.path.expanduser("~/.cache/nepnep-whisper/whisper-large-v3-turbo"),
)
MODEL_NAME = os.environ.get("NEPNEP_WHISPER_MODEL_NAME", "whisper-large-v3-turbo")

app = FastAPI(title="NepNep Whisper Server")

# 작업 id → {status, created, finished?, result?, error?, task}
JOBS: dict[str, dict[str, Any]] = {}


def log(message: str) -> None:
    # 시각이 없으면 어떤 요청이 언제 들어와 얼마나 걸렸는지 되짚을 수가 없다.
    print(f"{time.strftime('%H:%M:%S')} {message}", flush=True)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "model": MODEL_NAME,
        "model_path": MODEL_PATH,
        "jobs": len(JOBS),
    }


@app.get("/v1/models")
def models() -> dict[str, Any]:
    return {
        "object": "list",
        "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "local"}],
    }


class TranscribeOptions:
    """두 진입점이 똑같이 받는 폼 필드. 한 군데 적어 두고 나눠 쓴다."""

    def __init__(
        self,
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
        self.language = language
        self.prompt = prompt
        self.response_format = response_format
        self.temperature = temperature
        self.want_words = "word" in (
            timestamp_granularities + timestamp_granularities_bracket
        )


async def stash_upload(file: UploadFile) -> tuple[str, float]:
    """올라온 파일을 임시 파일로 떨군다. 경로와 크기(MB)를 준다."""
    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
    return tmp.name, os.path.getsize(tmp.name) / 1_048_576


def transcribe_file(path: str, options: TranscribeOptions) -> dict[str, Any]:
    return mlx_whisper.transcribe(
        path,
        path_or_hf_repo=MODEL_PATH,
        language=options.language,
        initial_prompt=options.prompt,
        temperature=options.temperature,
        word_timestamps=options.want_words,
        condition_on_previous_text=False,
        verbose=None,
    )


def build_payload(result: dict[str, Any], options: TranscribeOptions) -> dict[str, Any]:
    """전사 결과 → OpenAI `verbose_json` 모양."""
    segments = result.get("segments", [])
    payload: dict[str, Any] = {
        "task": "transcribe",
        "language": result.get("language", options.language or ""),
        "duration": segments[-1]["end"] if segments else 0.0,
        "text": result.get("text", "").strip(),
        "segments": segments,
    }
    if options.want_words:
        # OpenAI는 단어를 구간 안이 아니라 최상위 배열로 준다. 앱이 그쪽을 읽는다.
        payload["words"] = [w for seg in segments for w in seg.get("words", [])]
    return payload


def summarize(payload: dict[str, Any], elapsed: float) -> str:
    duration = payload["duration"]
    return (
        f"오디오 {duration:.0f}초 · 처리 {elapsed:.1f}초 "
        f"({duration / elapsed if elapsed else 0:.0f}배속) · "
        f"구간 {len(payload['segments'])}개"
    )


# MARK: - 맡기고 찾아가기 (앱이 쓰는 길)


@app.post("/v1/jobs")
async def create_job(
    file: UploadFile = File(...),
    options: TranscribeOptions = Depends(),
) -> dict[str, Any]:
    """전사를 맡기고 작업 id만 바로 돌려준다.

    올리는 즉시 응답이 끝나므로 아이폰이 백그라운드로 내려가도 잃을 연결이 없다.
    """
    purge_expired_jobs()
    tmp_path, size_mb = await stash_upload(file)

    job_id = uuid.uuid4().hex
    JOBS[job_id] = {
        "status": "running",
        "filename": file.filename,
        "created": time.monotonic(),
    }
    log(f"[작업 {job_id[:8]}] 맡음 — {file.filename} · {size_mb:.1f}MB")
    # 태스크를 붙들어 두지 않으면 파이썬이 도중에 거둬 갈 수 있다.
    JOBS[job_id]["task"] = asyncio.create_task(run_job(job_id, tmp_path, options))
    return {"id": job_id, "status": "running"}


async def run_job(job_id: str, tmp_path: str, options: TranscribeOptions) -> None:
    started = time.monotonic()
    job = JOBS[job_id]
    try:
        # 전사는 몇 분씩 걸리는 블로킹 호출이다. 스레드풀로 넘겨야 그동안 이벤트
        # 루프가 살아 있어 다른 연결을 돌볼 수 있다.
        result = await run_in_threadpool(lambda: transcribe_file(tmp_path, options))
        payload = build_payload(result, options)
        job.update(status="done", result=payload, finished=time.monotonic())
        log(f"[작업 {job_id[:8]}] 끝 — {summarize(payload, time.monotonic() - started)}")
    except Exception as exc:  # 업로드가 오디오가 아니거나 디코딩이 실패한 경우
        job.update(status="failed", error=str(exc), finished=time.monotonic())
        log(f"[작업 {job_id[:8]}] 실패 — {exc}")
    finally:
        os.unlink(tmp_path)


@app.get("/v1/jobs/{job_id}")
def read_job(job_id: str) -> dict[str, Any]:
    """끝났으면 결과를 통째로, 아직이면 도는 중이라고 답한다.

    결과는 감싸지 않고 그대로 펼쳐 준다 — 앱이 동기 응답을 읽던 코드로 똑같이
    읽을 수 있다.
    """
    job = JOBS.get(job_id)
    if job is None:
        raise HTTPException(404, "그런 작업이 없습니다 — 만료됐거나 서버가 다시 떴습니다")
    if job["status"] == "running":
        return {"status": "running", "elapsed": time.monotonic() - job["created"]}
    if job["status"] == "failed":
        return {"status": "failed", "error": {"message": job["error"]}}
    return {"status": "done", **job["result"]}


def purge_expired_jobs() -> None:
    """끝난 지 오래된 작업을 버린다. 도는 중인 것은 아무리 오래돼도 두고 본다."""
    cutoff = time.monotonic() - JOB_TTL_SECONDS
    stale = [
        job_id
        for job_id, job in JOBS.items()
        if job["status"] != "running" and job.get("finished", 0) < cutoff
    ]
    for job_id in stale:
        JOBS.pop(job_id, None)


# MARK: - OpenAI 규격 그대로 (curl로 찔러 보거나 다른 클라이언트가 붙을 때)


@app.post("/v1/audio/transcriptions")
async def transcriptions(
    file: UploadFile = File(...),
    options: TranscribeOptions = Depends(),
):
    tmp_path, size_mb = await stash_upload(file)
    started = time.monotonic()
    # 끝나야 로그가 찍히면 도는 중인지 죽은 건지 알 수가 없다. 시작도 찍는다.
    log(f"[전사] 시작 — {file.filename} · {size_mb:.1f}MB")

    job = asyncio.create_task(run_in_threadpool(lambda: transcribe_file(tmp_path, options)))

    def build_body() -> str:
        payload = build_payload(job.result(), options)
        log(f"[전사] 끝 — {file.filename} · {summarize(payload, time.monotonic() - started)}")

        if options.response_format == "text":
            return payload["text"]
        if options.response_format != "verbose_json":
            return json.dumps({"text": payload["text"]}, ensure_ascii=False)
        return json.dumps(payload, ensure_ascii=False)

    # 48분짜리면 4분을 기다리는데, 그동안 한 바이트도 안 흐르면 중간 장비가 연결을
    # 끊어 버린다. 도는 동안 공백을 흘려 보내 연결을 살아 있게 만든다 — JSON은 앞에
    # 붙은 공백을 무시하므로 파서는 그대로다.
    async def stream():
        try:
            while not job.done():
                yield HEARTBEAT
                await asyncio.sleep(HEARTBEAT_SECONDS)
            yield build_body().encode()
        except Exception as exc:
            log(f"[전사] 실패 — {file.filename} · {exc}")
            yield json.dumps({"error": {"message": str(exc)}}, ensure_ascii=False).encode()
        finally:
            os.unlink(tmp_path)

    media_type = "text/plain" if options.response_format == "text" else "application/json"
    return StreamingResponse(stream(), media_type=media_type)
