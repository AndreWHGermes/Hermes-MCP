import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config.dart';
import 'log_service.dart';
import 'settings_service.dart';

/// Проверка, является ли строка base64
bool _isBase64(String s) {
  // base64 содержит только A-Za-z0-9+/=
  // JSON начинается с { или [
  if (s.trim().startsWith('{') || s.trim().startsWith('[')) return false;
  // Если строка длинная и без пробелов — скорее всего base64
  return s.length > 50 && !s.contains(' ') && !s.contains('\n');
}

/// Декодирование ответа (WP может вернуть base64 вместо JSON)
String _decodeResponse(String body) {
  final trimmed = body.trim();
  if (_isBase64(trimmed)) {
    try {
      return utf8.decode(base64Decode(trimmed));
    } catch (_) {}
  }
  return body;
}

/// Результат проверки обновлений
class UpdateCheckResult {
  final bool updateAvailable;
  final String latestVersion;
  final String apkUrl;
  final String releaseNotes;
  final int buildNumber;

  const UpdateCheckResult({
    required this.updateAvailable,
    required this.latestVersion,
    required this.apkUrl,
    required this.releaseNotes,
    required this.buildNumber,
  });
}

/// Сервис для автоматической проверки и установки обновлений APK
class UpdateService {
  static final UpdateService _i = UpdateService._();
  factory UpdateService() => _i;
  UpdateService._();

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  /// URL версионного JSON-файла на сервере
  String get _versionJsonUrl =>
      '${SettingsService().serverUrl}${Config.apiVersion}';

  /// Проверить наличие обновления на сервере
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      LogService.info(
          'UpdateService: проверка $Config.appVersion → $_versionJsonUrl',
          tag: 'UPDATE');

      final resp = await http
          .get(Uri.parse(_versionJsonUrl))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        LogService.diag(
            'UpdateService: HTTP ${resp.statusCode}', tag: 'UPDATE');
        return _noUpdate();
      }

      // WP может закодировать ответ в base64 — декодируем
      final body = _decodeResponse(resp.body);
      final data = jsonDecode(body) as Map<String, dynamic>;
      final latestVersion = data['latestVersion'] as String? ?? '0.0.0';
      final apkUrl = data['apkUrl'] as String? ?? '';
      final releaseNotes = data['releaseNotes'] as String? ?? '';
      final buildNumber = data['buildNumber'] as int? ?? 0;

      LogService.diag(
          'UpdateService: latest=$latestVersion, build=$buildNumber',
          tag: 'UPDATE');

      // Сравниваем версии
      final current = _parseVersion(Config.appVersion);
      final latest = _parseVersion(latestVersion);

      final updateAvailable = _isNewer(latest, current);

      if (!updateAvailable) {
        LogService.diag(
            'UpdateService: обновлений нет', tag: 'UPDATE');
      }

      return UpdateCheckResult(
        updateAvailable: updateAvailable,
        latestVersion: latestVersion,
        apkUrl: apkUrl,
        releaseNotes: releaseNotes,
        buildNumber: buildNumber,
      );
    } catch (e) {
      LogService.diag('UpdateService: ошибка проверки: $e', tag: 'UPDATE');
      return _noUpdate();
    }
  }

  /// Скачать APK и запустить установку
  Future<bool> downloadAndInstall(
    BuildContext context, {
    required String apkUrl,
    required String version,
  }) async {
    if (_isDownloading) return false;
    _isDownloading = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final apkPath = '${dir.path}/HermesVoice-v$version.apk';

      LogService.info(
          'UpdateService: скачивание $apkUrl → $apkPath', tag: 'UPDATE');

      final response = await http
          .get(Uri.parse(apkUrl))
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        LogService.diag(
            'UpdateService: HTTP ${response.statusCode} при скачивании',
            tag: 'UPDATE');
        _isDownloading = false;
        return false;
      }

      final file = File(apkPath);
      await file.writeAsBytes(response.bodyBytes);

      LogService.info(
          'UpdateService: скачан ${response.bodyBytes.length ~/ 1024} KB',
          tag: 'UPDATE');

      // Запускаем установку через Intent
      await _installApk(context, file);

      _isDownloading = false;
      return true;
    } catch (e) {
      LogService.diag(
          'UpdateService: ошибка скачивания: $e', tag: 'UPDATE');
      _isDownloading = false;
      return false;
    }
  }

  /// Запуск Intent на установку APK
  Future<void> _installApk(BuildContext context, File apkFile) async {
    try {
      // На Android 7+ (API 25+) используем FileProvider через MethodChannel
      // Передаём путь к файлу в Kotlin, который настроит content:// URI
      await const MethodChannel('com.hermes.voice/installer')
          .invokeMethod('installApk', {
        'apkPath': apkFile.absolute.path,
      });
    } catch (e) {
      LogService.diag(
          'UpdateService: ошибка установки: $e', tag: 'UPDATE');
      // Используем захваченный контекст
      try {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка установки: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (_) {}
    }
  }

  /// Показать диалог "Доступно обновление"
  static Future<void> showUpdateDialog(
    BuildContext context, {
    required UpdateCheckResult result,
    required VoidCallback onDownload,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF2AABEE)),
            const SizedBox(width: 8),
            const Text('Доступно обновление'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Версия ${result.latestVersion}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (result.releaseNotes.isNotEmpty) ...[
              const Text(
                'Что нового:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                result.releaseNotes,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'v${Config.appVersion} → v${result.latestVersion}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Позже'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onDownload();
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Установить'),
          ),
        ],
      ),
    );
  }

  // ── Вспомогательные методы ───────────────────────────────────

  UpdateCheckResult _noUpdate() => const UpdateCheckResult(
        updateAvailable: false,
        latestVersion: '',
        apkUrl: '',
        releaseNotes: '',
        buildNumber: 0,
      );

  List<int> _parseVersion(String v) {
    return v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  bool _isNewer(List<int> a, List<int> b) {
    for (int i = 0; i < 3; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return false;
  }
}
