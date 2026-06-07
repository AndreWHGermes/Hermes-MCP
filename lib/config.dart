/// Hermes Voice App v7.0 — Конфигурация
///
/// Никаких Telegram токенов в APK!
/// Весь голосовой трафик напрямую через сервер.
class Config {
  // ═══════════════════════════════════════════════════════════════
  //  СЕРВЕР (по умолчанию — WordPress хостинг)
  // ═══════════════════════════════════════════════════════════════
  static const String defaultServerUrl = 'https://gptconnect.tw1.ru';

  // Версия приложения
  static const String appVersion = '7.0.0';

  // Build number
  static const int buildNumber = 70;

  // ═══════════════════════════════════════════════════════════════
  //  API ENDPOINTS (относительно serverUrl)
  // ═══════════════════════════════════════════════════════════════
  // Отправка голоса (POST multipart: wav + client_id)
  // Ответ: OGG аудиофайл или JSON с task_id
  static const String apiSend = '/voice/api/send';

  // Получение ответа по task_id (GET)
  static const String apiRespond = '/voice/api/respond';

  // Проверка статуса привязки (GET)
  static const String apiStatus = '/voice/api/status';

  // Привязка устройства (POST: client_id + auth_code)
  static const String apiLink = '/voice/api/link';

  // Проверка обновлений
  static const String apiVersion = '/voice/api/version.json';

  // Ping
  static const String apiPing = '/voice/api/ping';

  // ═══════════════════════════════════════════════════════════════
  //  БАКВАРДНАЯ СОВМЕСТИМОСТЬ (для telegram_service.dart)
  // ═══════════════════════════════════════════════════════════════
  static const String serverUrl = defaultServerUrl;
  static const String apiVoice = '/voice/api/send';
  static const String apiText = '/voice/api/send';
  static const String apiPoll = '/voice/api/respond';

  // ═══════════════════════════════════════════════════════════════
  //  SharedPreferences keys
  // ═══════════════════════════════════════════════════════════════
  static const String prefClientId = 'client_id';
  static const String prefServerUrl = 'server_url';
  static const String prefIsLinked = 'is_linked';

  // ═══════════════════════════════════════════════════════════════
  //  Лимиты
  // ═══════════════════════════════════════════════════════════════
  static const int maxRecordSeconds = 10;
  static const int requestTimeoutSeconds = 30;
  static const int authCodeTimeoutMinutes = 5;
}
