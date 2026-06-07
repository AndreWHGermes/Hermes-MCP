import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'log_service.dart';

// ── События от сервера ────────────────────────────────────────
class ServerEvent {
  final String type; // 'voice'|'text'|'diag'|'error'
  final String data;
  final Map<String, dynamic>? metadata;
  const ServerEvent(this.type, this.data, {this.metadata});
}

// ── HermesApiService — прямой HTTP-клиент к серверу ───────────
// Полная замена TelegramService. Вместо Isolate-based polling
// к api.telegram.org — простой HTTP-клиент к gptconnect.tw1.ru
// ──────────────────────────────────────────────────────────────
class TelegramService {
  static final TelegramService _i = TelegramService._();
  factory TelegramService() => _i;
  TelegramService._();

  // Серверный URL (токен НЕ хранится в приложении)
  String get _base => Config.serverUrl;

  // Периодический polling к серверу для получения ответов
  Timer? _pollTimer;
  bool _isPolling = false;

  // Статистика
  int totalSent = 0;
  int totalFailed = 0;
  DateTime? lastSendTime;

  // Колбеки
  Function(String url)? onVoiceMessage;
  Function(String text)? onCommand;
  Function(String msg)? onDiag;

  bool get isRunning => _isPolling;

  /// Инициализация (упрощена — токена больше нет)
  void init() {
    LogService.info('HermesApi: инициализирован (без токена в APK)', tag: 'API');
    LogService.diag('HermesApi: сервер = $_base', tag: 'API');
  }

  // ── Запуск polling к серверу ───────────────────────────────
  Future<void> startListening() async {
    LogService.info('HermesApi: запуск polling к $_base', tag: 'API');

    // Проверяем, жив ли сервер
    final pingOk = await _ping();
    if (!pingOk) {
      onDiag?.call('[❌] Сервер ${Config.serverUrl} недоступен');
      LogService.error('HermesApi: сервер не отвечает', tag: 'API');
      // Всё равно запускаем таймер — может заработает позже
    } else {
      onDiag?.call('[✅] Сервер ${Config.serverUrl} доступен');
    }

    _isPolling = true;

    // Polling каждые 3 секунды
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollResponses();
    });

    // Отправляем уведомление о старте через текстовый эндпоинт
    await sendText('✅ Hermes Voice v${Config.appVersion} активирован');
  }

  // ── Остановка polling ───────────────────────────────────────
  Future<void> stopListening() async {
    await sendText('⏹ Hermes Voice деактивирован');
    _isPolling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Ping сервера ────────────────────────────────────────────
  Future<bool> _ping() async {
    try {
      final resp = await http
          .get(Uri.parse(Config.apiPing))
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Poll ответов от сервера ─────────────────────────────────
  Future<void> _pollResponses() async {
    try {
      final resp = await http
          .get(Uri.parse(Config.apiPoll))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body);
      if (data['ok'] != true) return;

      final messages = data['messages'] as List?;
      if (messages == null || messages.isEmpty) return;

      for (final msg in messages) {
        final type = msg['type'] as String?;
        if (type == 'voice') {
          final url = msg['url'] as String?;
          if (url != null) {
            onVoiceMessage?.call(url);
          }
        } else if (type == 'text') {
          final text = msg['text'] as String?;
          if (text != null) {
            onCommand?.call(text);
          }
        }
      }
    } catch (e) {
      // Тихий провал — не спамим лог при каждой ошибке
    }
  }

  // ── Отправка голосового сообщения через сервер ─────────────
  Future<bool> sendVoiceFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        onDiag?.call('[❌] Файл не найден: $filePath');
        totalFailed++;
        return false;
      }

      final fileSize = await file.length();
      onDiag?.call('[ℹ] Отправка на сервер: ${fileSize ~/ 1024} KB');

      final uri = Uri.parse(Config.apiVoice);
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile(
          'voice',
          file.openRead(),
          fileSize,
          filename: 'voice.wav',
        ),
      );

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));

      if (streamed.statusCode == 200) {
        totalSent++;
        lastSendTime = DateTime.now();
        onDiag?.call('[ℹ] Отправлено на сервер ✓');
        _cleanupFile(filePath);
        return true;
      } else {
        final body = await streamed.stream.bytesToString();
        totalFailed++;
        onDiag?.call('[❌] Сервер: HTTP ${streamed.statusCode}: $body');
        return false;
      }
    } catch (e) {
      totalFailed++;
      onDiag?.call('[❌] sendVoiceFile: $e');
      return false;
    }
  }

  // ── Отправка текста через сервер ───────────────────────────
  Future<bool> sendText(String text) async {
    try {
      final resp = await http
          .post(
            Uri.parse(Config.apiText),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['ok'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Удаление временного файла после отправки
  void _cleanupFile(String path) {
    try {
      File(path).delete();
      onDiag?.call('[ℹ] Временный файл удалён');
    } catch (_) {}
  }
}
