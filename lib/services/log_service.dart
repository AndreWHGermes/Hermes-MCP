import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// LogService — единое хранилище логов
// Хранит до 500 последних записей в SharedPreferences
// Каждая запись: время + тип + сообщение
// ============================================================

enum LogLevel { info, success, warning, error, diag, debug }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry({
    required this.time,
    required this.level,
    this.tag = '',
    required this.message,
  });

  String get formatted {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final tagStr = tag.isEmpty ? '' : '[$tag] ';
    return '$h:$m:$s $tagStr$message';
  }

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    time: DateTime.parse(json['time'] as String),
    level: LogLevel.values.firstWhere(
      (l) => l.name == json['level'],
      orElse: () => LogLevel.info,
    ),
    tag: json['tag'] as String? ?? '',
    message: json['message'] as String? ?? '',
  );
}

class LogService {
  static final LogService _i = LogService._();
  factory LogService() => _i;
  LogService._();

  static const int _maxEntries = 500;
  late SharedPreferences _prefs;
  final List<LogEntry> _entries = [];
  bool _initialized = false;

  /// Инициализация — загружает сохранённые логи
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _loadFromDisk();
    _initialized = true;
  }

  /// Добавить запись в лог
  void log(LogLevel level, String message, {String tag = ''}) {
    final entry = LogEntry(time: DateTime.now(), level: level, tag: tag, message: message);
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    _saveToDisk();
  }

  // Удобные методы
  static void info(String msg, {String tag = ''}) => _i.log(LogLevel.info, msg, tag: tag);
  static void success(String msg, {String tag = ''}) => _i.log(LogLevel.success, msg, tag: tag);
  static void warning(String msg, {String tag = ''}) => _i.log(LogLevel.warning, msg, tag: tag);
  static void error(String msg, {String tag = ''}) => _i.log(LogLevel.error, msg, tag: tag);
  static void diag(String msg, {String tag = ''}) => _i.log(LogLevel.diag, msg, tag: tag);
  static void debug(String msg, {String tag = ''}) => _i.log(LogLevel.debug, msg, tag: tag);

  /// Все записи (свежие первые)
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Очистить лог
  void clear() {
    _entries.clear();
    _saveToDisk();
  }

  /// Полный текст лога для копирования
  String get fullText {
    return _entries.map((e) => e.formatted).join('\n');
  }

  // ── Сохранение в SharedPreferences ──

  void _saveToDisk() {
    if (!_initialized) return;
    try {
      final jsonList = _entries.map((e) => e.toJson()).toList();
      _prefs.setString('app_log', jsonEncode(jsonList));
    } catch (_) {}
  }

  void _loadFromDisk() {
    try {
      final raw = _prefs.getString('app_log');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      _entries.addAll(
        list
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
            .where((e) => e.message.isNotEmpty)
      );
      // Обрезаем до максимума
      while (_entries.length > _maxEntries) {
        _entries.removeLast();
      }
    } catch (_) {
      _entries.clear();
    }
  }
}

