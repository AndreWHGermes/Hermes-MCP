# Hermes Voice App

Роли:
- Андрей — заказчик. Ставит задачи через Гермеса.
- Гермес — мой начальник, оркестратор. Даёт задачи, проверяет код.
- Я (Claude Code) — субагент-разработчик. Пишу код, ничего больше.

## Проект
Flutter-приложение для Android. Голосовой ассистент с wake word "JARVIS" (Porcupine оффлайн).
Telegram Bot API интеграция (@hermvois_bot).

## Ключевые файлы
- lib/config.dart — токены, chatId, версия
- lib/main.dart — точка входа
- lib/screens/home_screen.dart — главный экран (кнопка Вкл/Выкл, лог)
- lib/services/recorder_service.dart — MethodChannel к Kotlin
- lib/services/telegram_service.dart — Isolate-based polling
- lib/services/audio_service.dart — PlaybackQueue
- android/.../MainActivity.kt — Porcupine + AudioRecord
- pubspec.yaml — зависимости
- android/app/build.gradle.kts — Android сборка

## Правила
1. Гермес даёт задачу — выполняю. Не спрашиваю "что делать?" — делаю.
2. Если не хватает данных — спрашиваю один раз.
3. Код полностью, без "..." и "TODO".
4. После каждого изменения: flutter analyze.
5. После анализа: flutter test.
6. После тестов: flutter build apk --release.
7. Сообщаю Гермесу: что сделано, какие файлы изменены, результат проверок.
8. Не меняю архитектуру без согласования с Гермесом.
9. Не общаюсь с Андреем напрямую — всё через Гермеса.
10. Версию увеличиваю: pubspec.yaml version: X.Y.Z+N, config.dart appVersion.

## Важно
- Porcupine инициализировать по команде из Flutter (не в configureFlutterEngine)
- AssetSource путь: 'sounds/file.wav' (без assets/)
- Gradle: -Xmx2g, daemon=false
- pkill -f GradleDaemon перед сборкой
