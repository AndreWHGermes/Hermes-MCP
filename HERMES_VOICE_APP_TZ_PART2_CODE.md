# Hermes Voice App — Исходный код проекта (v2.1.0)

## Структура проекта

```
hermes_voice_app/
├── android/
│   ├── app/
│   │   ├── build.gradle.kts
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/.../MainActivity.kt
│   ├── build.gradle.kts
│   └── settings.gradle.kts
├── lib/
│   ├── config.dart
│   ├── main.dart
│   ├── screens/
│   │   └── home_screen.dart
│   └── services/
│       ├── audio_service.dart
│       ├── recorder_service.dart
│       └── telegram_service.dart
├── assets/sounds/
│   ├── power_on.wav
│   ├── power_off.wav
│   ├── beep_start.wav
│   └── beep_end.wav
└── pubspec.yaml
```

---

## 1. pubspec.yaml

```yaml
name: hermes_voice_app
description: "Голосовое приложение для связи с Hermes через Telegram"
publish_to: 'none'
version: 2.1.0+21

environment:
  sdk: ^3.7.2

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.2.0
  audioplayers: ^6.1.0
  path_provider: ^2.1.0
  flutter_background_service: ^5.0.0
  flutter_local_notifications: ^18.0.0
  permission_handler: ^11.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/sounds/power_on.wav
    - assets/sounds/power_off.wav
    - assets/sounds/beep_start.wav
    - assets/sounds/beep_end.wav
```

---

## 2. lib/config.dart

```dart
class Config {
  // @hermvois_bot — единственный бот, всё через него
  static const String botToken = '8887199277:AAE...полный_токен...';

  // Telegram ID Андрея
  static const String chatId = '399924132';

  // Версия приложения
  static const String appVersion = '2.1.0';

  // URL для проверки обновлений
  static const String versionCheckUrl = 'https://acetennis.ru/voice-app-version.txt';

  // Триггерное слово
  static const String triggerWord = 'гермес';

  // Порог тишины для окончания записи команды (миллисекунды)
  static const int silenceTimeoutMs = 1500;

  // Порог энергии звука для детекции речи (0-32767)
  static const int speechEnergyThreshold = 800;

  // Порог для детекции тишины после команды
  static const int silenceEnergyThreshold = 300;
}
```

---

## 3. lib/main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/home_screen.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}

Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'hermes_foreground',
    'Hermes Voice',
    description: 'Hermes слушает микрофон',
    importance: Importance.low,
  );

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'hermes_foreground',
      initialNotificationTitle: 'Hermes Voice',
      initialNotificationContent: 'Слушаю... скажи "Гермес"',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initBackgroundService();
  runApp(const HermesVoiceApp());
}

class HermesVoiceApp extends StatelessWidget {
  const HermesVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Voice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2AABEE),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
```

---

## 4. lib/screens/home_screen.dart

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/telegram_service.dart';
import '../services/audio_service.dart';
import '../services/recorder_service.dart';
import '../config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _telegram = TelegramService();
  final _audio = AudioService();
  final _recorder = RecorderService();

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
  }

  void _setupCallbacks() {
    _telegram.onVoiceMessage = (url) async {
      _log_('🔊 Ответ Hermes получен, воспроизвожу', LogType.success);
      await _audio.playAsset('sounds/power_on.wav');
      await _audio.playVoice(url);
    };

    _telegram.onCommand = (text) {
      _log_('💬 Текст от Hermes: $text', LogType.info);
    };

    _telegram.onDiag = (msg) {
      _log_(msg, msg.contains('❌') ? LogType.error : LogType.diag);
    };

    _audio.onPlaybackComplete = () {
      _log_('✅ Воспроизведение завершено', LogType.success);
    };
    _audio.onLog = (msg) => _log_(msg, LogType.diag);

    _recorder.onLog = (msg) => _log_(msg, LogType.diag);

    _recorder.onTriggerDetected = () async {
      _log_('🎯 "Гермес" услышан! Записываю команду...', LogType.success);
      await _audio.playAsset('sounds/beep_start.wav');
    };

    _recorder.onRecordingReady = (path) async {
      _log_('📤 Команда записана, отправляю...', LogType.info);
      await _audio.playAsset('sounds/beep_end.wav');
      final ok = await _telegram.sendVoiceFile(path);
      if (ok) {
        _log_('✅ Команда отправлена Hermes', LogType.success);
      } else {
        _log_('❌ Ошибка отправки', LogType.error);
      }
    };

    _recorder.onStateChanged = (state) {
      setState(() => _recState = state);
      if (state == RecorderState.listening) {
        _pulseCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.value = 1.0;
      }
    };
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

  Future<void> _activate() async {
    if (_isStarting) return;
    _isStarting = true;

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
    await _telegram.startListening();

    final micOk = await _recorder.startListening();
    if (!micOk) {
      _log_('❌ Не удалось запустить микрофон', LogType.error);
    }

    _keepaliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_telegram.isRunning) {
        _log_('[ping] Telegram connected', LogType.diag);
      }
    });

    setState(() => _isActive = true);
    await _audio.playAsset('sounds/power_on.wav');
    _log_('🟢 Активирован. Скажи "Гермес" чтобы дать команду', LogType.success);
    _isStarting = false;
  }

  Future<void> _deactivate() async {
    _keepaliveTimer?.cancel();
    await _recorder.stopListening();
    await _telegram.stopListening();
    await _audio.stopPlayback();
    FlutterBackgroundService().invoke('stopService');

    setState(() {
      _isActive = false;
      _recState = RecorderState.idle;
    });

    await _audio.playAsset('sounds/power_off.wav');
    _log_('🔴 Деактивирован', LogType.info);
  }

  Future<void> _pttStart() async {
    await _recorder.forceStartRecording();
    _log_('🎙 PTT: запись...', LogType.info);
  }

  Future<void> _pttStop() async {
    await _recorder.forceStopRecording();
    _log_('🎙 PTT: стоп', LogType.info);
  }

  Future<void> _checkUpdate() async {
    _log_('Проверяю обновления...', LogType.diag);
    final v = await _telegram.checkUpdateUrl();
    if (!mounted) return;
    if (v != null && v != Config.appVersion) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Text('Новая версия: $v\nТекущая: ${Config.appVersion}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      _log_('✓ Версия актуальна (${Config.appVersion})', LogType.success);
    }
  }

  // [UI build method — стандартный Flutter Scaffold с градиентом,
  //  иконкой, статусом, кнопкой Вкл/Выкл, PTT кнопкой,
  //  кнопкой проверки обновлений и логом событий]
  // Полный код см. в файле проекта

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
    super.dispose();
  }
}

enum LogType { success, error, info, diag }

class _LogEntry {
  final String text;
  final Color color;
  _LogEntry(this.text, LogType type)
      : color = switch (type) {
          LogType.success => const Color(0xFF2ECC71),
          LogType.error => const Color(0xFFE53935),
          LogType.info => Colors.white70,
          LogType.diag => Colors.white38,
        };
}
```

---

## 5. lib/services/recorder_service.dart

```dart
import 'dart:async';
import 'package:flutter/services.dart';

enum RecorderState { idle, listening, recording }

class RecorderService {
  static final RecorderService _i = RecorderService._();
  factory RecorderService() => _i;
  RecorderService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel _channel =
      MethodChannel('com.hermes.voice/recorder');

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  Function()? onTriggerDetected;
  Function(String path)? onRecordingReady;
  Function(String msg)? onLog;
  Function(RecorderState)? onStateChanged;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onTriggerDetected':
        _state = RecorderState.recording;
        onStateChanged?.call(_state);
        onLog?.call('🎯 Триггер "Гермес" обнаружен!');
        onTriggerDetected?.call();
        break;

      case 'onRecordingReady':
        final path = call.arguments as String;
        _state = RecorderState.listening;
        onStateChanged?.call(_state);
        onLog?.call('✅ Запись готова: $path');
        onRecordingReady?.call(path);
        break;

      case 'onLog':
        onLog?.call('[NAT] ${call.arguments}');
        break;

      case 'onStateChanged':
        final stateStr = call.arguments as String;
        switch (stateStr) {
          case 'listening':
            _state = RecorderState.listening;
            break;
          case 'recording':
            _state = RecorderState.recording;
            break;
          default:
            _state = RecorderState.idle;
        }
        onStateChanged?.call(_state);
        break;
    }
  }

  Future<bool> startListening() async {
    try {
      final result = await _channel.invokeMethod<bool>('startListening', {
        'triggerWord': 'гермес',
        'speechThreshold': 800,
        'silenceThreshold': 300,
        'silenceTimeoutMs': 1500,
      });
      if (result == true) {
        _state = RecorderState.listening;
        onStateChanged?.call(_state);
        onLog?.call('🎙 Микрофон активен, жду "Гермес"...');
      }
      return result ?? false;
    } on PlatformException catch (e) {
      onLog?.call('❌ startListening: ${e.message}');
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
      _state = RecorderState.idle;
      onStateChanged?.call(_state);
      onLog?.call('🔇 Микрофон выключен');
    } on PlatformException catch (e) {
      onLog?.call('❌ stopListening: ${e.message}');
    }
  }

  Future<void> forceStartRecording() async {
    try {
      await _channel.invokeMethod('forceStartRecording');
    } on PlatformException catch (e) {
      onLog?.call('❌ forceStartRecording: ${e.message}');
    }
  }

  Future<void> forceStopRecording() async {
    try {
      await _channel.invokeMethod('forceStopRecording');
    } on PlatformException catch (e) {
      onLog?.call('❌ forceStopRecording: ${e.message}');
    }
  }
}
```
