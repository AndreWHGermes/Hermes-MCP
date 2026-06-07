#!/usr/bin/env python3
"""Cloud Code: ModelService — скачивание Vosk модели."""
import sys, subprocess, os, json
sys.path.insert(0, "/opt/data/vault")
from run_claude import get_key

key = get_key("ds01")
env = os.environ.copy()
env["ANTHROPIC_BASE_URL"] = "https://api.deepseek.com/anthropic"
env["ANTHROPIC_AUTH_TOKEN"] = key
env["ANTHROPIC_MODEL"] = "deepseek-chat"
env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = "deepseek-chat"
env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

TASK = """Гермес: Добавь СКАЧИВАНИЕ МОДЕЛИ VOSK в приложение.

АРХИТЕКТУРА:
- APK будет без Vosk модели (маленький, ~20 MB)
- При первом запуске приложение скачивает модель ZIP (23 MB)
- URL модели: https://gptconnect.tw1.ru/wp-content/uploads/vosk-model.zip
- Распаковывает ZIP в filesDir/model-ru/
- После распаковки — кнопка "Включить" становится активной

ЧТО СДЕЛАТЬ:

1. pubspec.yaml — добавить dependency: archive: ^3.0.0 (для распаковки ZIP)

2. Создать lib/services/model_service.dart:
   - Future<bool> checkModel() — проверяет есть ли model-ru в appDir
   - Future<String> downloadModel(void Function(double) onProgress) — скачивает ZIP
     с http.get и stream, распаковывает через archive,
     onProgress(0.0..1.0) для UI
   - String? cachedPath — кеширует путь после первой проверки

   URL модели вынести в Config: static const String modelUrl = "..."

3. lib/screens/home_screen.dart:
   - Если модели нет: big blue button "📥 Скачать модель (23 MB)"
   - Во время загрузки: LinearProgressIndicator + процент + "Распаковка..."
   - После загрузки: button "Включить" как обычно
   - Если ошибка загрузки: "❌ Ошибка: ... Попробовать снова"
   - Всё через setState, состояние хранить в _HomeScreenState

4. lib/main.dart:
   - При старте проверять модель через ModelService()
   - Если нет — передать флаг в HomeScreen

5. lib/config.dart:
   - Добавить static const String modelUrl = "https://gptconnect.tw1.ru/wp-content/uploads/vosk-model.zip"

6. Не менять MainActivity.kt — initVosk() и copyAssetDirectory() остаются как есть.
   Модель будет лежать в appDir/model-ru/, MainActivity получит этот путь
   через MethodChannel из recorder_service.dart.

ПОСЛЕ КАЖДОГО ИЗМЕНЕНИЯ: flutter analyze
ПОСЛЕ ВСЕГО: flutter build apk --release --target-platform android-arm64

Начинай!"""

cmd = ["claude", "--bare", "-p", "--dangerously-skip-permissions",
       "--add-dir", "/opt/data/hermes_voice_app", TASK]

result = subprocess.run(cmd, capture_output=True, text=True, timeout=600, env=env)
print("=== STDOUT ===")
print(result.stdout[:3000])
if result.stderr:
    print("=== STDERR ===")
    print(result.stderr[:500])
print(f"\n=== EXIT CODE: {result.returncode} ===")
