#!/usr/bin/env python3
"""Отправить задачу Cloud Code с авто-подтверждением на запись."""
import sys, json, subprocess, os

key_path = "/opt/data/vault/keys.json"
with open(key_path) as f:
    data = json.load(f)
key = data["keys"]["ds01"]["value"]

env = os.environ.copy()
env["ANTHROPIC_BASE_URL"] = "https://api.deepseek.com/anthropic"
env["ANTHROPIC_AUTH_TOKEN"] = key
env["ANTHROPIC_MODEL"] = "deepseek-chat"
env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = "deepseek-chat"
env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
env["CLAUDE_CODE_ALLOW_DANGEROUSLY_SKIP_PERMISSIONS"] = "1"

TASK = """Гермес: Исправь 2 бага. У тебя полное разрешение на запись.

БАГ 1 — Race condition в MainActivity.kt
mainLoop() вызывает audioRecord.read() на IO корутине.
stopListening() вызывает audioRecord.release() на main thread.
Если release() во время read() — IllegalStateException без try-catch → crash.
Исправь: оберни read() в mainLoop() в try-catch.

БАГ 2 — setState после dispose в home_screen.dart
onStateChanged = (state) {
  setState(() => _recState = state); // нет if (!mounted)
}
Добавь if (!mounted) return; перед setState.

После каждого: flutter analyze. По готовности — скажи результат."""

cmd = ["claude", "--bare", "-p", "--dangerously-skip-permissions",
       "--output-format", "json", "--add-dir", "/opt/data/hermes_voice_app",
       TASK]

result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env=env)

try:
    out = json.loads(result.stdout)
    print("=== ОТВЕТ CLOUD CODE ===")
    print(out.get("result", "")[:2000])
    print(f"\nСессия: {out.get('session_id', '')}")
except:
    print("=== STDOUT ===")
    print(result.stdout[:2000])
    if result.stderr:
        print("\n=== STDERR ===")
        print(result.stderr[:500])
