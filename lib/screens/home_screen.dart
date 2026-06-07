import 'dart:async';
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/voice_service.dart';
import '../services/recorder_service.dart';
import '../services/update_service.dart';
import '../config.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _voice = VoiceService();
  final _recorder = RecorderService();
  final _audioPlayer = AudioPlayer();

  bool _isActive = false;
  bool _isStarting = false; // защита от двойного нажатия
  RecorderState _recState = RecorderState.idle;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Лог событий
  final List<_LogEntry> _log = [];

  // Таймер keepalive
  Timer? _keepaliveTimer;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _setupCallbacks();

    // Проверка обновлений при старте
    _checkForUpdates();
  }

  void _setupCallbacks() {
    // Ответ от сервера (OGG файл)
    _voice.onVoiceResponse = (oggPath) async {
      _log_('🔊 Ответ Hermes получен, воспроизвожу', LogType.success);
      await _playOgg(oggPath);
    };

    // Диагностика
    _voice.onDiag = (msg) {
      _log_(msg, msg.contains('❌') ? LogType.error : LogType.diag);
    };

    _audioPlayer.onPlayerComplete.listen((_) {
      _log_('✅ Воспроизведение завершено', LogType.success);
    });

    _recorder.onLog = (msg) => _log_(msg, LogType.diag);

    _recorder.onTriggerDetected = () async {
      _log_('🎯 Wake word услышан! Записываю команду...', LogType.success);
      await _playSystemSound('sounds/beep_start.wav');
    };

    _recorder.onRecordingReady = (path) async {
      _log_('📤 Команда записана, отправляю...', LogType.info);
      await _playSystemSound('sounds/beep_end.wav');
      final ok = await _voice.sendWav(path);
      if (ok) {
        _log_('✅ Команда отправлена на сервер', LogType.success);
      } else {
        _log_('❌ Ошибка отправки', LogType.error);
      }
    };

    _recorder.onStateChanged = (state) {
      if (!mounted) return;
      setState(() => _recState = state);
      if (state == RecorderState.listening) {
        _pulseCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.value = 1.0;
      }
    };
  }

  Future<void> _playSystemSound(String assetPath) async {
    final player = AudioPlayer();
    try {
      await player.play(AssetSource(assetPath));
      player.onPlayerComplete.listen((_) => player.dispose());
    } catch (e) {
      player.dispose();
    }
  }

  Future<void> _playOgg(String oggPath) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(oggPath));
    } catch (e) {
      _log_('❌ Ошибка воспроизведения OGG: $e', LogType.error);
    }
  }

  void _log_(String msg, LogType type) {
    if (!mounted) return;
    setState(() {
      final n = DateTime.now();
      _log.insert(0, _LogEntry(
        '${n.hour.toString().padLeft(2,'0')}:'
        '${n.minute.toString().padLeft(2,'0')}:'
        '${n.second.toString().padLeft(2,'0')} $msg',
        type,
      ));
      if (_log.length > 100) _log.removeLast();
    });
  }

  /// Проверка обновлений на сервере
  Future<void> _checkForUpdates() async {
    final result = await UpdateService().checkForUpdate();
    if (!mounted) return;
    if (!result.updateAvailable) return;

    _log_('🔄 Доступно обновление v${result.latestVersion}', LogType.info);

    UpdateService.showUpdateDialog(
      context,
      result: result,
      onDownload: () => _downloadAndInstall(result),
    );
  }

  Future<void> _downloadAndInstall(UpdateCheckResult result) async {
    _log_('⬇ Скачиваю v${result.latestVersion}...', LogType.info);
    final ok = await UpdateService().downloadAndInstall(
      context,
      apkUrl: result.apkUrl,
      version: result.latestVersion,
    );
    if (ok) {
      _log_('✅ APK скачан, запущена установка', LogType.success);
    } else {
      _log_('❌ Ошибка загрузки обновления', LogType.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Не удалось скачать обновление'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _activate() async {
    if (_isStarting) return;
    _isStarting = true;
    try {
      final mic = await Permission.microphone.request();
      await Permission.notification.request();

      if (!mic.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Нужен доступ к микрофону')),
          );
        }
        return;
      }

      await FlutterBackgroundService().startService();

      final micOk = await _recorder.startListening(
        wakeWord: 'Гермес',
        speechThreshold: 800,
        silenceThreshold: 300,
        silenceTimeoutMs: 1500,
      );
      if (!micOk) {
        _log_('❌ Не удалось запустить микрофон', LogType.error);
      }

      _keepaliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _voice.ping().then((ok) {
          if (ok) {
            _log_('[ping] Сервер доступен', LogType.diag);
          }
        });
      });

      setState(() => _isActive = true);
      await _playSystemSound('sounds/power_on.wav');
      _log_('🟢 Активирован. Скажи "Гермес" чтобы дать команду', LogType.success);
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _deactivate() async {
    _keepaliveTimer?.cancel();
    await _recorder.stopListening();
    await _audioPlayer.stop();
    FlutterBackgroundService().invoke('stopService');

    setState(() {
      _isActive = false;
      _recState = RecorderState.idle;
    });

    await _playSystemSound('sounds/power_off.wav');
    _log_('🔴 Деактивирован', LogType.info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Hermes Voice', style: TextStyle(color: Colors.white)),
        actions: [
          // Кнопка настроек
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'Настройки',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          // Кнопка проверки обновлений
          IconButton(
            icon: const Icon(Icons.system_update, color: Colors.white70),
            tooltip: 'Проверить обновления',
            onPressed: () async {
              _log_('🔄 Проверяю обновления...', LogType.info);
              final messenger = ScaffoldMessenger.of(context);
              final result = await UpdateService().checkForUpdate();
              if (!mounted) return;
              if (result.updateAvailable) {
                UpdateService.showUpdateDialog(
                  context,
                  result: result,
                  onDownload: () => _downloadAndInstall(result),
                );
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('✅ Установлена последняя версия'),
                    backgroundColor: Color(0xFF2ECC71),
                  ),
                );
              }
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A8FD1), Color(0xFF1A2535)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            // ── Иконка + статус ────────────────────────────
            Expanded(
              flex: 3,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Пульсирующая иконка
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (ctx, child) => Transform.scale(
                        scale: _pulseAnim.value,
                        child: child,
                      ),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: _recState == RecorderState.recording
                              ? const Color(0xFFE53935)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: (_recState == RecorderState.recording
                                      ? Colors.red
                                      : const Color(0xFF2AABEE))
                                  .withValues(alpha: 0.4),
                              blurRadius: 25,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          _recState == RecorderState.recording
                              ? Icons.mic
                              : _recState == RecorderState.listening
                                  ? Icons.hearing
                                  : Icons.headset_mic,
                          size: 60,
                          color: _recState == RecorderState.recording
                              ? Colors.white
                              : const Color(0xFF1A8FD1),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      'Hermes Voice',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusText(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Кнопка Включить/Выключить ─────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _buildActionButton(),
            ),

            // ── Лог событий ───────────────────────────────
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(
                        'ЛОГ СОБЫТИЙ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'отправлено: ${_voice.totalSent} | '
                        'ошибок: ${_voice.totalFailed}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _log.clear()),
                        child: Text(
                          'очистить',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Expanded(
                      child: _log.isEmpty
                          ? Center(
                              child: Text(
                                'Нажми "Включить"',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              child: SelectableText.rich(
                                TextSpan(
                                  children: _log.map((e) => TextSpan(
                                    text: '${e.text}\n',
                                    style: TextStyle(
                                      color: e.color,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  )).toList(),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Версия ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'v${Config.appVersion}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 10,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return _BigButton(
      label: _isActive ? 'Выключить' : 'Включить',
      icon: Icons.power_settings_new,
      color: _isActive ? const Color(0xFFE53935) : const Color(0xFF2ECC71),
      onTap: _isActive ? _deactivate : _activate,
    );
  }

  String _statusText() {
    if (!_isActive) return '⚪ Ожидание';
    switch (_recState) {
      case RecorderState.listening:
        return '🟢 Слушаю... скажи "Гермес"';
      case RecorderState.recording:
        return '🔴 Записываю команду...';
      case RecorderState.idle:
        return '🟡 Запуск микрофона...';
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _keepaliveTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

enum LogType { success, error, info, diag }

class _LogEntry {
  final String text;
  final LogType type;
  const _LogEntry(this.text, this.type);

  Color get color {
    switch (type) {
      case LogType.success: return const Color(0xFF66BB6A);
      case LogType.error:   return const Color(0xFFEF5350);
      case LogType.info:    return const Color(0xFF29B6F6);
      case LogType.diag:    return Colors.white38;
    }
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
