#!/usr/bin/env python3
"""Отправить задачу Cloud Code на исправление багов."""
import sys, json
sys.path.insert(0, "/opt/data/vault")
from run_claude import run_claude

TASK = """Гермес: Нашёл 2 критических бага. Исправь их прямо в файлах.

БАГ 1 — Race condition в MainActivity.kt
mainLoop() вызывает audioRecord.read() на IO корутине.
stopListening() вызывает audioRecord.release() на main thread.
Если release() вызывается во время read() — IllegalStateException.
Нет try-catch → crash.
Исправь: оберни read() в try-catch в mainLoop().

БАГ 2 — setState после dispose в home_screen.dart
_recorder.onStateChanged = (state) {
  setState(() => _recState = state); // нет проверки mounted
}
Исправь: добавь if (!mounted) return; перед setState.

После каждого исправления: flutter analyze.
После обоих: скажи результат."""

if __name__ == "__main__":
    result = run_claude(["--bare", "-p", "--output-format", "json", TASK])
    try:
        out = json.loads(result["stdout"])
        print("=== ОТВЕТ CLOUD CODE ===")
        print(out.get("result", "")[:2000])
        sid = out.get("session_id", "")
        if sid:
            with open("/opt/data/chronicler/last_cc_session.txt", "w") as f:
                f.write(sid)
    except:
        print("=== RAW STDOUT ===")
        print(result["stdout"][:2000])
        print("\n=== STDERR ===")
        print(result["stderr"][:500])
