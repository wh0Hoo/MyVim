import json
import sys
import os
from pathlib import Path

try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)

mode = data.get("permission_mode", "")
file_path = data.get("tool_input", {}).get("file_path", "")
plans_dir = Path(os.path.expanduser("~/.claude/plans/")).resolve()

try:
    in_plans = Path(file_path).resolve().is_relative_to(plans_dir)
except (ValueError, OSError):
    in_plans = False

if mode == "plan" and not in_plans:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason":
                f"Plan mode: '{file_path}' 편집 불가. 계획 파일({plans_dir})만 수정 가능합니다."
        }
    }))
    sys.exit(0)

# auto mode에서도 파일 수정 시 경고 — 계획만 요청된 경우 구현으로 넘어가지 않도록 상기
if mode != "plan":
    print(
        "⚠️ [HOOK] 파일 수정 시도 감지. "
        "사용자가 명시적으로 구현(파일 수정)을 요청했는지 확인하라. "
        "계획·정리·설계만 요청된 경우 즉시 중단하고 허가를 구하라.",
        file=sys.stderr
    )
