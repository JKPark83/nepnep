#!/usr/bin/env bash
# 생성물 파일 편집 차단 (PreToolUse / Edit·Write·NotebookEdit)
#
# 왜: 이 프로젝트에서 .xcodeproj·Info.plist는 전부 xcodegen이 project.yml에서
# 만들어 내는 생성물이고 .gitignore 대상이다. 직접 고치면 다음 `xcodegen generate`에서
# 조용히 날아가고, 그 사이 빌드가 나는 바람에 고쳐진 것처럼 보인다 —
# 가장 알아채기 어려운 실패라 아예 막는다.
#
# 대상: ios/project.yml이 만드는 ios/NepNep.xcodeproj·Info.plist 2종,
# 그리고 spike/NepNepSpike/project.yml이 만드는 spike의 .xcodeproj.
#
# 실패 방식: 경로를 못 읽거나(jq 실패·payload 이상) 패턴에 안 걸리면 exit 0으로
# 조용히 통과시킨다. 차단은 오탐이 나도 사람이 바로 알아채지만, 훅이 죽어서
# 모든 편집이 막히는 쪽은 훨씬 나쁘다.
set -uo pipefail

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -z "$path" ] && exit 0

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

case "$path" in
  */project.pbxproj|*.xcodeproj/*|*.xcodeproj)
    deny "생성물이라 편집할 수 없습니다: ${path}
*.xcodeproj는 xcodegen이 같은 디렉터리의 project.yml에서 생성합니다.
project.yml(앱은 ios/project.yml)을 고치고 그 디렉터리에서 \`xcodegen generate\`를 실행하세요."
    ;;
  */NepNep/Info.plist)
    deny "생성물이라 편집할 수 없습니다: ${path}
Info.plist는 ios/project.yml의 targets.NepNep.info.properties에서 생성됩니다.
거기를 고치고 \`cd ios && xcodegen generate\`를 실행하세요."
    ;;
  */NepNepWidgets/Info.plist)
    deny "생성물이라 편집할 수 없습니다: ${path}
Info.plist는 ios/project.yml의 targets.NepNepWidgets.info.properties에서 생성됩니다.
거기를 고치고 \`cd ios && xcodegen generate\`를 실행하세요."
    ;;
esac

exit 0
