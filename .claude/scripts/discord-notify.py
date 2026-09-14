import sys
import json
import os
import traceback
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_PATH = os.path.join(SCRIPT_DIR, "hook-debug.log")
LOG_MAX_BYTES = 1_000_000
LOG_KEEP_LINES = 200

def log(msg):
    try:
        if os.path.getsize(LOG_PATH) > LOG_MAX_BYTES:
            with open(LOG_PATH, encoding="utf-8", errors="replace") as f:
                tail = f.readlines()[-LOG_KEEP_LINES:]
            with open(LOG_PATH, "w", encoding="utf-8") as f:
                f.writelines(tail)
    except OSError:
        pass
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(msg + "\n")

def format_tool_call(tool_name, tool_input):
    tool_map = {
        "WebFetch": ("Fetch", "url"),
        "Edit": ("Edit", "file_path"),
        "MultiEdit": ("Edit", "file_path"),
        "Write": ("Write", "file_path"),
        "Bash": ("Bash", "command"),
        "Glob": ("Glob", "pattern"),
        "Grep": ("Grep", "pattern"),
        "Read": ("Read", "file_path"),
    }
    short_name, key = tool_map.get(tool_name, (tool_name, None))
    arg = tool_input.get(key, "") if key else ""
    return f"\n{short_name}({arg})" if arg else f"\n{short_name}"

try:
    # utf-8-sig: 메모장 등으로 직접 편집하면 BOM이 붙는데, utf-8 로 열면 그때 죽는다.
    with open(os.path.join(SCRIPT_DIR, "discord-config.json"), encoding="utf-8-sig") as f:
        WEBHOOK_URL = json.load(f)["webhook_url"]

    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    log(f"FIRED: {raw}")

    try:
        data = json.loads(raw)
    except Exception:
        data = {}

    hook_event = data.get("hook_event_name", "")
    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    cwd = data.get("cwd", "")

    if hook_event == "Notification":
        if data.get("notification_type") == "permission_prompt":
            sys.exit(0)
        content = f"## 알림\n>>> {cwd}\n``` \nClaude 대기중\n ```"
    elif hook_event == "Stop":
        content = f"## 작업 완료\n>>> {cwd}\n``` \nClaude 작업 완료\n ```"
    elif hook_event == "PostCompact":
        content = f"## Compact 완료\n>>> {cwd}\n``` \nSession Compact 완료\n ```"
    elif hook_event == "PermissionRequest":
        tool_call = format_tool_call(tool_name, tool_input)
        content = f"## 권한 요청\n>>> {cwd}\n``` \nClaude가 다음 권한 요청 중 :{tool_call}\n ```"
    else:
        content = f"## 알림\n```\n{hook_event}\n```"

    payload = json.dumps({"content": content, "username": "Claude Code"}, ensure_ascii=False).encode("utf-8")

    req = urllib.request.Request(
        WEBHOOK_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "DiscordBot (claude-code-hook, 1.0)",
        },
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        log(f"OK: {resp.status}")

except Exception:
    log(f"EXCEPTION:\n{traceback.format_exc()}")

sys.exit(0)
