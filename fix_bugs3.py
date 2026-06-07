#!/usr/bin/env python3
"""Исправление багов — полный доступ, без подтверждений."""
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

TASK = """Я Гермес. У тебя полный доступ к серверу. Исправь баги.

Ты в /opt/data/hermes_voice_app/
Используй Bash и Edit для редактирования файлов напрямую.
Не спрашивай разрешения — просто делай.

БАГ 1: android/.../MainActivity.kt
Найди mainLoop() где audioRecord.read().
Оберни read() в try-catch, чтобы release() не крашил приложение.

БАГ 2: lib/screens/home_screen.dart
Найди onStateChanged = (state) { setState ...
Добавь if (!mounted) return; перед setState

После каждого: flutter analyze.
После обоих: сообщи результат."""

cmd = ["claude", "--add-dir", "/opt/data/hermes_voice_app",
       "--dangerously-skip-permissions", "-p", TASK]

result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env=env)
print(result.stdout[:3000])
if result.stderr:
    print("=== STDERR ===")
    print(result.stderr[:1000])
