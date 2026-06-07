import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config.dart';
import 'log_service.dart';
import 'settings_service.dart';

// ============================================================
// VoiceService — HTTP клиент для прямой связи с сервером
// v7.0 — полная замена TelegramService
// 
// POST /voice/api/send  (WAV + client_id) → получаем OGG
// GET  /voice/api/status (client_id) → статус привязки
// ============================================================

class VoiceService {
  static final VoiceService _i = VoiceService._();
  factory VoiceService() => _i;
  VoiceService._();

  // Статистика
  int totalSent = 0;
  int totalFailed = 0;
  DateTime? lastSendTime;

  // Колбеки
  Function(String oggPath)? onVoiceResponse;
  Function(String msg)? onDiag;
  Function(bool connected)? onConnectionStatus;

  // ── Информация о сервере ────────────────────────────────────
  String get _baseUrl => SettingsService().serverUrl;

  // ── Генерация клиентского UUID ──────────────────────────────
  String _generateUuid() {
    final r = Random();
    final hex = List.generate(16, (_) => r.nextInt(256));
    // Формат UUID: 8-4-4-4-12
    hex[6] = (hex[6] & 0x0f) | 0x40; // version 4
    hex[8] = (hex[8] & 0x3f) | 0x80; // variant
    final parts = [
      hex.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      hex.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      hex.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      hex.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      hex.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ];
    return parts.join('-');
  }

  /// Генерирует и сохраняет client_id (если ещё нет)
  Future<String> ensureClientId() async {
    final settings = SettingsService();
    await settings.init();
    if (settings.hasClientId) {
      return settings.clientId;
    }
    final uuid = _generateUuid();
    settings.clientId = uuid;
    LogService.info('VoiceService: client_id сгенерирован: $uuid', tag: 'VOICE');
    return uuid;
  }

  /// Получить client_id
  Future<String> getClientId() async {
    await SettingsService().init();
    return SettingsService().clientId;
  }

  /// Генерация 4-значного кода аутентификации
  String generateAuthCode() {
    final r = Random();
    return (1000 + r.nextInt(9000)).toString();
  }

  // ── Проверка статуса привязки ──────────────────────────────
  Future<Map<String, dynamic>> checkStatus(String clientId) async {
    try {
      final url = Uri.parse('$_baseUrl${Config.apiStatus}')
          .replace(queryParameters: {'client_id': clientId});
      final resp = await http
          .get(url)
          .timeout(Duration(seconds: Config.requestTimeoutSeconds));
      final body = utf8.decode(resp.bodyBytes);
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      LogService.error('VoiceService: checkStatus error: $e', tag: 'VOICE');
      return {'ok': false, 'error': 'Сервер недоступен'};
    }
  }

  // ── Попытка привязки ────────────────────────────────────────
  Future<bool> tryLink(String clientId, String authCode) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl${Config.apiLink}'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'client_id': clientId,
              'auth_code': authCode,
            }),
          )
          .timeout(Duration(seconds: Config.requestTimeoutSeconds));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (e) {
      LogService.error('VoiceService: tryLink error: $e', tag: 'VOICE');
      return false;
    }
  }

  // ── Отправка WAV на сервер ──────────────────────────────────
  // POST /voice/api/send (multipart: wav + client_id)
  // Ответ: OGG аудиофайл (синхронный режим)
  Future<bool> sendWav(String wavPath) async {
    try {
      final file = File(wavPath);
      if (!await file.exists()) {
        onDiag?.call('[❌] Файл WAV не найден: $wavPath');
        totalFailed++;
        return false;
      }

      final fileSize = await file.length();
      final clientId = await getClientId();
      if (clientId.isEmpty) {
        onDiag?.call('[❌] client_id не найден');
        totalFailed++;
        return false;
      }

      onDiag?.call('[ℹ] Отправка на сервер: ${fileSize ~/ 1024} KB');

      final uri = Uri.parse('$_baseUrl${Config.apiSend}');
      final request = http.MultipartRequest('POST', uri);
      request.fields['client_id'] = clientId;
      request.files.add(
        http.MultipartFile(
          'voice',
          file.openRead(),
          fileSize,
          filename: 'voice.wav',
        ),
      );

      final streamed = await request
          .send()
          .timeout(Duration(seconds: Config.requestTimeoutSeconds));

      if (streamed.statusCode == 200) {
        totalSent++;
        lastSendTime = DateTime.now();
        final bytes = await streamed.stream.toBytes();

        // Определяем тип ответа: OGG или JSON
        if (bytes.length >= 4 &&
            bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67) {
          // Это OGG файл — сохраняем и проигрываем
          final tmpDir = await _tmpDir();
          final oggPath = '${tmpDir.path}/response_${DateTime.now().millisecondsSinceEpoch}.ogg';
          await File(oggPath).writeAsBytes(bytes);
          onDiag?.call('[✅] Получен OGG ответ (${bytes.length ~/ 1024} KB)');
          onVoiceResponse?.call(oggPath);
        } else {
          // JSON ответ
          final body = utf8.decode(bytes);
          try {
            final data = jsonDecode(body) as Map<String, dynamic>;
            if (data['task_id'] != null) {
              // Асинхронный режим — нужно опрашивать
              final taskId = data['task_id'];
              onDiag?.call('[ℹ] Асинхронный режим, task_id=$taskId');
              _pollResponse(taskId);
            } else if (data['error'] != null) {
              onDiag?.call('[❌] Сервер: ${data['error']}');
              totalFailed++;
              return false;
            } else {
              onDiag?.call('[❌] Неизвестный ответ сервера');
              totalFailed++;
              return false;
            }
          } catch (_) {
            onDiag?.call('[❌] Ответ не OGG и не JSON');
            totalFailed++;
            return false;
          }
        }
        _cleanupFile(wavPath);
        return true;
      } else {
        final body = await streamed.stream.bytesToString();
        totalFailed++;
        onDiag?.call('[❌] Сервер: HTTP ${streamed.statusCode}: $body');
        return false;
      }
    } catch (e) {
      totalFailed++;
      onDiag?.call('[❌] Ошибка sendWav: $e');
      return false;
    }
  }

  // ── Poll асинхронного ответа ─────────────────────────────────
  Future<void> _pollResponse(String taskId) async {
    onDiag?.call('[ℹ] Ожидаю ответ...');
    final clientId = await getClientId();
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final uri = Uri.parse('$_baseUrl${Config.apiRespond}')
            .replace(queryParameters: {
          'task_id': taskId,
          'client_id': clientId,
        });
        final resp = await http
            .get(uri)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final bytes = resp.bodyBytes;
          if (bytes.length >= 4 &&
              bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67) {
            final tmpDir = await _tmpDir();
            final oggPath = '${tmpDir.path}/response_$taskId.ogg';
            await File(oggPath).writeAsBytes(bytes);
            onDiag?.call('[✅] Получен OGG ($taskId)');
            onVoiceResponse?.call(oggPath);
            return;
          }
          // Может быть статус "processing"
          final body = utf8.decode(bytes);
          try {
            final data = jsonDecode(body) as Map<String, dynamic>;
            if (data['status'] == 'processing') {
              continue; // ещё обрабатывается
            }
            if (data['error'] != null) {
              onDiag?.call('[❌] ${data['error']}');
              return;
            }
          } catch (_) {
            // не JSON — пробуем как OGG
            continue;
          }
        }
      } catch (e) {
        onDiag?.call('[ℹ] Ожидание... ($e)');
      }
    }
    onDiag?.call('[❌] Таймаут ожидания ответа');
  }

  // ── Ping ──────────────────────────────────────────────────────
  Future<bool> ping() async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl${Config.apiPing}'))
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── Утилиты ──────────────────────────────────────────────────
  void _cleanupFile(String path) {
    try {
      File(path).delete();
    } catch (_) {}
  }

  Future<Directory> _tmpDir() async {
    final dir = await getTemporaryDirectory();
    return dir;
  }
}
