#!/bin/bash
# 맥에서 전사 서버를 띄운다. 테일스케일 주소로만 열어 공용 네트워크에는 뜨지 않는다.
#
#   ./run.sh              # 테일스케일 주소:8927
#   HOST=0.0.0.0 ./run.sh # 로컬 네트워크에도 열기
set -euo pipefail
cd "$(dirname "$0")"

TS_IP="$(tailscale ip -4 2>/dev/null || true)"
HOST="${HOST:-${TS_IP:-127.0.0.1}}"
PORT="${PORT:-8927}"

echo "전사 서버 → http://${HOST}:${PORT}"
exec .venv/bin/uvicorn server:app --host "$HOST" --port "$PORT" --timeout-keep-alive 600
