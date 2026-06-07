#!/usr/bin/env python3
"""
Запускает Claude Code прямо в директории проекта с полным доступом.
Передаёт задачу и ждёт результат.
"""
import sys, json
sys.path.insert(0, "/opt/data/vault")
from run_claude import run_claude

TASK = """ТЫ — Cloud Code, субагент-разработчик. Я — Гермес, твой начальник.

Ты находишься в корне проекта /opt/data/hermes_voice_app/
CLAUDE.md прочитан — знаешь правила.

ЗАДАЧА: Проанализируй проект и сделай рабочую версию.

ШАГ 1: Прочитай ВСЕ файлы проекта (у тебя полный доступ)
ШАГ 2: Запусти flutter analyze — проверь текущее состояние
ШАГ 3: Исправь ВСЕ ошибки, которые найдешь
ШАГ 4: После каждого исправления — flutter analyze
ШАГ 5: Когда flutter analyze чистый — flutter build apk --release

ИЗВЕСТНАЯ ПРОБЛЕМА: log_screen.dart отсутствует — это может быть compile error.
settings_screen.dart импортирует log_screen.dart — нужно проверить.

НАЧИНАЙ. Первым делом прочитай все файлы и запусти flutter analyze."""

if __name__ == "__main__":
    result = run_claude(["--bare", "-p", "--output-format", "json", TASK])
    try:
        out = json.loads(result["stdout"])
        print("=== ОТВЕТ CLOUD CODE ===")
        print(out.get("result", "")[:3000])
        print(f"\n=== СЕССИЯ: {out.get('session_id', 'N/A')} ===")
        sid = out.get("session_id", "")
        if sid:
            with open("/opt/data/chronicler/last_cc_session.txt", "w") as f:
                f.write(sid)
        print(f"\nРаундов: {out.get('num_turns', '?')}")
        print(f"Стоимость: ${out.get('total_cost_usd', 0):.2f}")
    except:
        print("=== RAW STDOUT ===")
        print(result["stdout"][:3000])
        print("\n=== STDERR ===")
        print(result["stderr"][:500])
