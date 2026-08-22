#!/usr/bin/env bash
# Swift 파일 자동 포맷 (PostToolUse / Edit·Write)
#
# 왜: 편집 직후에 포맷을 맞춰 두면 리뷰 diff에 스타일 잡음이 섞이지 않는다.
#
# 지금은 조건이 안 맞아 아무 일도 하지 않는다 — 의도된 상태다.
# 이 저장소에는 SwiftFormat도, .swiftformat 설정 파일도 없다. 설정 없이
# 기본값으로 돌리면 기존 코드를 전부 남의 스타일로 갈아엎어
# "기존 스타일을 바꾸지 않는다"는 원칙을 정면으로 어긴다.
#
# 켜는 법 (둘 다 있어야 동작한다):
#   1. brew install swiftformat
#   2. 저장소 루트에 .swiftformat 작성 — 기존 코드에서 규칙을 뽑아내려면
#      `swiftformat --inferoptions ios/NepNep > .swiftformat`
#   3. 처음 한 번은 전체에 적용하고 별도 커밋으로 분리한다 (diff 잡음 격리)
#
# 실패 방식: 어느 조건이든 안 맞으면 exit 0으로 조용히 통과한다.
# 포매터가 실패해도 편집 자체를 되돌리지는 않는다.
set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0

case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac

command -v swiftformat >/dev/null 2>&1 || exit 0

root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.swiftformat" ] || exit 0

swiftformat --config "$root/.swiftformat" "$file" >/dev/null 2>&1 || true
exit 0
