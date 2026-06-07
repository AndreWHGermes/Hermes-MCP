import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';

// ============================================================
// LogScreen — полный лог событий для диагностики
// Можно скопировать целиком через кнопку
// ============================================================

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _log = LogService();
  List<LogEntry> _entries = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Обновляем лог каждые 2 секунды, чтобы видеть новые записи
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _entries = _log.entries;
    });
  }

  void _copyAll() {
    final text = _log.fullText;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лог пуст'), duration: Duration(seconds: 1)),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Лог скопирован! Отправь его в чат с Hermes'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _clearLog() {
    _log.clear();
    _refresh();
  }

  Color _colorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.error:   return const Color(0xFFEF5350);
      case LogLevel.warning:  return const Color(0xFFFFA726);
      case LogLevel.success: return const Color(0xFF66BB6A);
      case LogLevel.info:    return const Color(0xFF42A5F5);
      case LogLevel.debug:   return Colors.grey;
      case LogLevel.diag:    return Colors.white54;
    }
  }

  String _iconForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.error:   return '❌';
      case LogLevel.warning:  return '⚠️';
      case LogLevel.success: return '✅';
      case LogLevel.info:    return 'ℹ️';
      case LogLevel.debug:   return '🔍';
      case LogLevel.diag:    return '🔧';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Лог событий'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Копировать всё',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Очистить лог',
            onPressed: _clearLog,
          ),
        ],
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('Лог пуст', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _entries.length,
              itemBuilder: (ctx, i) {
                final e = _entries[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          _iconForLevel(e.level),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          e.formatted,
                          style: TextStyle(
                            color: _colorForLevel(e.level),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
