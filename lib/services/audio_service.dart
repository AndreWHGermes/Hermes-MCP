import 'dart:async';
import 'dart:collection';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

// ============================================================
// AudioService v3.0
// - PlaybackQueue — ответы воспроизводятся последовательно
// - Системные звуки отдельным плеером (поверх очереди)
// ============================================================

class AudioService {
  static final AudioService _i = AudioService._();
  factory AudioService() => _i;
  AudioService._() {
    _player.onPlayerComplete.listen((_) => _onComplete());
  }

  final AudioPlayer _player = AudioPlayer();

  // Очередь воспроизведения голосовых ответов
  final Queue<String> _queue = Queue();
  bool _isPlaying = false;

  // Статистика
  int totalPlayed = 0;

  Function()? onPlaybackComplete;
  Function(String)? onLog;

  // ── Добавить URL в очередь ──────────────────────────────
  void enqueue(String url) {
    _queue.add(url);
    onLog?.call('📥 В очередь добавлен (всего: ${_queue.length})');
    if (!_isPlaying) {
      _playNext();
    }
  }

  // ── Воспроизвести следующий из очереди ──────────────────
  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _isPlaying = false;
      onPlaybackComplete?.call();
      return;
    }

    _isPlaying = true;
    final url = _queue.removeFirst();

    try {
      onLog?.call('🔊 Воспроизвожу ответ Hermes');
      await _player.play(UrlSource(url));
    } catch (e) {
      onLog?.call('❌ Ошибка воспроизведения: $e');
      _isPlaying = false;
      _playNext(); // пробуем следующий
    }
  }

  void _onComplete() {
    totalPlayed++;
    _playNext(); // автоматически следующий
  }

  // ── Воспроизвести голосовой ответ (через очередь) ──────
  Future<void> playVoice(String url) async {
    // Скачиваем файл локально для стабильного воспроизведения
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        await File(filePath).writeAsBytes(response.bodyBytes);
        enqueue(filePath); // добавляем в очередь локальный файл
      } else {
        onLog?.call('❌ Скачивание: HTTP ${response.statusCode}');
      }
    } catch (e) {
      onLog?.call('❌ playVoice: $e');
    }
  }

  // ── Системные звуки (вне очереди, поверх) ───────────────
  Future<void> playAsset(String assetPath) async {
    final player = AudioPlayer();
    try {
      await player.play(AssetSource(assetPath));
      player.onPlayerComplete.listen((_) => player.dispose());
    } catch (e) {
      // play() упал — чистим плеер сразу
      player.dispose();
      onLog?.call('⚠️ Системный звук: $e');
    }
  }

  // ── Стоп и очистка очереди ──────────────────────────────
  Future<void> stopPlayback() async {
    _queue.clear();
    _isPlaying = false;
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
