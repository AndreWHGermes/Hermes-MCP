# Hermes Voice App — Техническое задание + Исходный код

## Описание проекта

Android приложение для голосового управления через Telegram. Связка: телефон (Android) ↔ Telegram Bot ↔ Hermes Agent (сервер).

## Архитектура

```
Пользователь → [Android App] → Telegram Bot API → [Hermes Agent на сервере]
                ↑                                        ↓
                └──────── Telegram Bot API ←──────────────┘
```

Android приложение работает в фоне, слушает входящие сообщения из Telegram чата через getUpdates (long polling). 
Когда пользователь говорит триггер-слово "Гермес" → приложение записывает аудио → отправляет в Telegram ботом → 
я (Hermes Agent) обрабатываю → отправляю голосовой ответ в Telegram → приложение его подхватывает и воспроизводит.

## Текущее состояние

- Приложение собирается (flutter build apk --release), APK ~20MB
- Звуки включения/выключения работают (WAV файлы через AssetSource audioplayers)
- При нажатии "Включить" приложение запускает polling Telegram API
- **Проблема: приложение не получает обновления из Telegram.** 
  - [DIAG] сообщения не приходят в чат
  - Команды (/play) не доходят до приложения
  - Голосовые сообщения не подхватываются
  - При этом sendText (отправка сообщений) работает — текст "[Голосовой режим активирован]" приходит

## Файлы проекта

### 1. pubspec.yaml (зависимости)

```yaml
name: hermes_voice_app
description: "Голосовое приложение для связи с Hermes через Telegram"
publish_to: 'none'
version: 1.0.0+1

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
  permission_handler: ^11.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/sounds/power_on.wav
    - assets/sounds/power_off.wav
```

### 2. lib/config.dart

```dart
class Config {
  static String get botToken => '8751647587:AAHlCpRcBajCKWT1TjQcnf0aPBJFWaYyzRAg';
  static String get chatId => '399924132';
  static String get appVersion => '1.0.3';
  static String get versionCheckUrl => 'https://acetennis.ru/voice-app-version.txt';
  static String get apkDownloadUrl => 'https://acetennis.ru/hermes_voice_app.apk';
  static String get triggerWord => 'гермес';

  static Future<void> initialize() async {
    // Будущая инициализация
  }
}
```

### 3. lib/main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:hermes_voice_app/services/telegram_service.dart';
import 'package:hermes_voice_app/services/audio_service.dart';
import 'package:hermes_voice_app/screens/home_screen.dart';
import 'package:hermes_voice_app/config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.initialize();
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

### 4. lib/screens/home_screen.dart

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hermes_voice_app/services/telegram_service.dart';
import 'package:hermes_voice_app/services/audio_service.dart';
import 'package:hermes_voice_app/config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TelegramService _telegram = TelegramService();
  final AudioService _audio = AudioService();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  bool _isActive = false;
  bool _showInfo = true;
  bool _isCheckingUpdate = false;

  Future<void> _playSfx(String assetPath) async {
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource(assetPath));
    } catch (e) {
      print('SFX error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _setupCallbacks();
  }

  void _setupCallbacks() {
    _telegram.onVoiceMessage = (url) {
      if (_isActive) {
        _audio.playVoice(url);
      }
    };
    _telegram.onCommand = (text) async {
      if (text == '/play' || text == '/тест') {
        _playSfx('sounds/power_on.wav');
      }
    };
  }

  Future<void> _checkVersion() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    final latestVersion = await _telegram.checkUpdateUrl();
    if (!mounted) return;

    if (latestVersion != null && latestVersion != Config.appVersion) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Text('Новая версия: $latestVersion\nТекущая: ${Config.appVersion}\n\nСкачать и установить?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _downloadUpdate();
              },
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('У вас актуальная версия ✓'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    setState(() => _isCheckingUpdate = false);
  }

  Future<void> _downloadUpdate() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Откройте Telegram — APK уже там')),
      );
    }
  }

  Future<void> _toggleActive() async {
    if (!_isActive) {
      var micStatus = await Permission.microphone.request();
      var notifyStatus = await Permission.notification.request();

      if (!micStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нужен доступ к микрофону')),
          );
        }
        return;
      }

      setState(() => _isActive = true);
      _telegram.startListening();
      _telegram.sendText('[Голосовой режим активирован]');
      _playSfx('sounds/power_on.wav');
      if (mounted) setState(() => _showInfo = false);
    } else {
      setState(() => _isActive = false);
      _telegram.stopListening();
      _audio.stopPlayback();
      _telegram.sendText('[Голосовой режим деактивирован]');
      _playSfx('sounds/power_off.wav');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2AABEE),
              Color(0xFF232E3F),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.headset_mic,
                          size: 60,
                          color: Color(0xFF2AABEE),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Hermes Voice',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isActive ? 'Режим разговора' : 'Режим ожидания',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionButton(
                      label: 'Включить',
                      icon: Icons.power_settings_new,
                      color: const Color(0xFF31B545),
                      isActive: _isActive,
                      onTap: _isActive ? null : _toggleActive,
                    ),
                    const SizedBox(height: 24),
                    _buildActionButton(
                      label: 'Выключить',
                      icon: Icons.power_settings_new,
                      color: const Color(0xFFE53935),
                      isActive: !_isActive,
                      onTap: _isActive ? _toggleActive : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 200,
                      child: OutlinedButton.icon(
                        onPressed: _isCheckingUpdate ? null : _checkVersion,
                        icon: _isCheckingUpdate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.update, color: Colors.white, size: 18),
                        label: const Text(
                          'Проверить обновления',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_showInfo)
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Как это работает:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 8),
                      _InfoRow(icon: Icons.mic, text: 'Нажми "Включить" и говори "Гермес..."'),
                      _InfoRow(icon: Icons.send, text: 'Команда уходит в Telegram'),
                      _InfoRow(icon: Icons.headphones, text: 'Ответ автоматически в наушники'),
                      _InfoRow(icon: Icons.update, text: 'Приложение само проверяет обновления'),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'v${Config.appVersion}',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isActive ? 0.4 : 1.0,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
```

### 5. lib/services/telegram_service.dart

```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config.dart';

class TelegramService {
  static final TelegramService _instance = TelegramService._();
  factory TelegramService() => _instance;
  TelegramService._();

  final String _baseUrl = 'https://api.telegram.org/bot${Config.botToken}';
  int _lastUpdateId = 0;
  bool _isRunning = false;
  Function(String)? onVoiceMessage;
  Function(String)? onCommand;

  Future<void> _sendDiag(String text) async {
    try {
      final url = Uri.parse('$_baseUrl/sendMessage');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': Config.chatId,
          'text': '[DIAG] $text',
        }),
      );
    } catch (_) {}
  }

  Future<void> startListening() async {
    _isRunning = true;
    await _sendDiag('Начинаю слушать чат ${Config.chatId}');
    while (_isRunning) {
      try {
        await _pollUpdates();
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        print('Poll error: $e');
        await _sendDiag('Ошибка polling: $e');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  void stopListening() {
    _isRunning = false;
  }

  Future<void> _pollUpdates() async {
    final url = Uri.parse('$_baseUrl/getUpdates?offset=$_lastUpdateId&timeout=10');
    final response = await http.get(url);
    if (response.statusCode != 200) {
      await _sendDiag('getUpdates вернул ${response.statusCode}');
      return;
    }

    final data = jsonDecode(response.body);
    if (data['ok'] != true) {
      await _sendDiag('getUpdates ok=false');
      return;
    }

    final resultCount = (data['result'] as List).length;
    if (resultCount > 0) {
      await _sendDiag('Получено $resultCount обновлений');
    }

    for (final update in data['result']) {
      _lastUpdateId = update['update_id'] + 1;
      final message = update['message'];
      if (message == null) {
        await _sendDiag('update без message');
        continue;
      }

      final chatId = message['chat']?['id']?.toString() ?? 'null';
      final fromId = message['from']?['id']?.toString() ?? 'null';
      final hasVoice = message['voice'] != null;
      final hasText = message['text'] != null;

      await _sendDiag('Получено сообщение: chat=$chatId from=$fromId voice=$hasVoice text=$hasText');

      if (hasVoice && chatId == Config.chatId) {
        final fileId = message['voice']['file_id'];
        final duration = message['voice']['duration'];
        await _sendDiag('Обнаружено голосовое! file_id=$fileId duration=${duration}s');
        final voiceUrl = await _getFileUrl(fileId);
        if (voiceUrl != null && onVoiceMessage != null) {
          await _sendDiag('Воспроизвожу голосовое: $voiceUrl');
          onVoiceMessage!(voiceUrl);
        } else {
          await _sendDiag('Не удалось получить URL голосового или нет callback');
        }
      }

      if (hasText) {
        final text = message['text'] as String;
        if (fromId == Config.chatId) {
          await _sendDiag('Текстовая команда от пользователя: "$text"');
          if (onCommand != null) {
            onCommand!(text);
          }
        }
      }
    }
  }

  Future<String?> _getFileUrl(String fileId) async {
    final url = Uri.parse('$_baseUrl/getFile?file_id=$fileId');
    final response = await http.get(url);
    if (response.statusCode != 200) {
      await _sendDiag('getFile вернул ${response.statusCode}');
      return null;
    }

    final data = jsonDecode(response.body);
    if (data['ok'] != true) {
      await _sendDiag('getFile ok=false');
      return null;
    }

    final filePath = data['result']['file_path'];
    final fullUrl = 'https://api.telegram.org/file/bot${Config.botToken}/$filePath';
    await _sendDiag('URL голосового: $fullUrl');
    return fullUrl;
  }

  Future<bool> sendVoice(String filePath) async {
    try {
      final uri = Uri.parse('$_baseUrl/sendVoice');
      final request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = Config.chatId;
      request.files.add(await http.MultipartFile.fromPath('voice', filePath));
      final response = await request.send();
      final success = response.statusCode == 200;
      await _sendDiag('sendVoice: ${success ? "успешно" : "ошибка ${response.statusCode}"}');
      return success;
    } catch (e) {
      print('Send voice error: $e');
      await _sendDiag('sendVoice exception: $e');
      return false;
    }
  }

  Future<bool> sendText(String text) async {
    try {
      final url = Uri.parse('$_baseUrl/sendMessage');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': Config.chatId,
          'text': text,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Send text error: $e');
      return false;
    }
  }

  Future<String?> checkUpdateUrl() async {
    try {
      final url = Uri.parse(Config.versionCheckUrl);
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return response.body.trim();
      }
    } catch (_) {}
    return null;
  }
}
```

### 6. lib/services/audio_service.dart

```dart
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

enum AudioState { idle, listening, recording, playing }

class AudioService {
  static final AudioService _instance = AudioService._();
  factory AudioService() => _instance;
  AudioService._();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  AudioState _state = AudioState.idle;

  AudioState get state => _state;
  bool get isPlaying => _isPlaying;

  Function(String)? onRecordingComplete;

  Future<void> playVoice(String url) async {
    try {
      _state = AudioState.playing;
      _isPlaying = true;

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        await _player.play(DeviceFileSource(filePath));
      }

      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _state = AudioState.idle;
      });
    } catch (e) {
      print('Play error: $e');
      _isPlaying = false;
      _state = AudioState.idle;
    }
  }

  void stopPlayback() {
    _player.stop();
    _isPlaying = false;
    _state = AudioState.idle;
  }

  void dispose() {
    _player.dispose();
  }
}
```

### 7. android/app/build.gradle.kts

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hermes.hermes_voice_app"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.hermes.hermes_voice_app"
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

## Известные проблемы

1. **getUpdates не работает** — приложение не получает обновления из Telegram Bot API.
   - Текстовые сообщения отправляются успешно (sendMessage работает)
   - Но polling getUpdates не возвращает новые сообщения
   - Пользователь в России, использует VPN
   - Вероятные причины: (а) неправильная обработка offset, (б) проблемы с сетью на Android
   
2. **Нет записи микрофона** — приложение не записывает голос пользователя. 
   Только принимает голосовые от бота (которые тоже не работают из-за проблемы 1).
   Нужен пакет flutter_sound или record для записи.

3. **Нет детекции триггер-слова** — "Гермес" пока не распознаётся.
   Нужен Vosk, Porcupine или простая запись с последующей STT.

4. **Нет foreground service** — Android может убить приложение в фоне.
   Нужен persistent notification с иконкой.

## Вопросы для ревью

1. Почему getUpdates не получает сообщения, хотя sendMessage работает?
2. Как правильно реализовать фоновый сервис на Android 10+?
3. Какой пакет лучше для записи аудио (flutter_sound, record, audio_recorder)?
4. Как сделать детекцию триггер-слова на телефоне (offline)?
5. Есть ли альтернатива Telegram Bot API для Android приложения (прямой WebSocket к серверу?)

## Окружение сборки

- Flutter SDK 3.29.2
- Android SDK platform 35
- NDK 27.0.12077973
- OpenJDK 21
- Ubuntu/Debian x86_64
