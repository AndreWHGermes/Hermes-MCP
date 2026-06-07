# Hermes Voice App v7.0

Роли:
- Андрей — заказчик. Ставит задачи через Гермеса.
- Гермес — мой начальник, оркестратор. Даёт задачи, проверяет код.
- Я (Claude Code) — субагент-разработчик. Пишу код, ничего больше.

## Проект
Flutter-приложение для Android. Голосовой ассистент с wake word "Гермес".
Google SpeechRecognizer (встроен в Android) для распознавания речи.
Прямое HTTP-соединение с сервером gptconnect.tw1.ru (voice/api/*).

## Ключевые файлы
- lib/config.dart — версия, API endpoints, лимиты
- lib/main.dart — точка входа
- lib/screens/home_screen.dart — главный экран (кнопка Вкл/Выкл, лог)
- lib/screens/auth_screen.dart — экран аутентификации (привязка к серверу)
- lib/services/voice_service.dart — HTTP клиент для прямой связи с сервером
- lib/services/recorder_service.dart — MethodChannel к Kotlin (AudioRecord)
- lib/services/audio_service.dart — воспроизведение OGG/WAV
- lib/services/settings_service.dart — SharedPreferences обёртка
- lib/services/log_service.dart — логирование
- lib/services/update_service.dart — проверка обновлений
- android/.../MainActivity.kt — Google SpeechRecognizer + AudioRecord + wake word
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
- VoiceService — единственный сервис для связи с сервером (замена TelegramService)
- Wake word "Гермес" обрабатывается в Kotlin (MainActivity)
- Google SpeechRecognizer встроен в Android — не требует загрузки моделей
- AssetSource путь: 'sounds/file.wav' (без assets/)
- Gradle: -Xmx2g, daemon=false
- pkill -f GradleDaemon перед сборкой
