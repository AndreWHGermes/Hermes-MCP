# Hermes Voice App — Исходный код (продолжение)

## 6. android/.../MainActivity.kt (ключевой файл — нативная сторона)

```kotlin
package com.hermes.hermes_voice_app

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.hermes.voice/recorder"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    private var methodChannel: MethodChannel? = null
    private var audioRecord: AudioRecord? = null
    private var listenerJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var speechThreshold = 800
    private var silenceThreshold = 300
    private var silenceTimeoutMs = 1500L

    enum class Mode { IDLE, LISTENING, RECORDING }
    @Volatile private var mode = Mode.IDLE
    @Volatile private var forcedRecording = false
    @Volatile private var stopRequested = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    speechThreshold = call.argument<Int>("speechThreshold") ?: 800
                    silenceThreshold = call.argument<Int>("silenceThreshold") ?: 300
                    silenceTimeoutMs = (call.argument<Int>("silenceTimeoutMs") ?: 1500).toLong()
                    val ok = startListening()
                    result.success(ok)
                }
                "stopListening" -> {
                    stopAll()
                    result.success(null)
                }
                "forceStartRecording" -> {
                    forcedRecording = true
                    if (mode == Mode.LISTENING) {
                        mode = Mode.RECORDING
                        sendToFlutter("onTriggerDetected", null)
                        sendToFlutter("onStateChanged", "recording")
                    } else {
                        sendLog("forceStartRecording в режиме IDLE, игнорирую")
                    }
                    result.success(null)
                }
                "forceStopRecording" -> {
                    forcedRecording = false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startListening(): Boolean {
        if (!checkPermission()) {
            sendLog("Нет разрешения RECORD_AUDIO")
            return false
        }

        stopAll()

        val bufferSize = maxOf(
            AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT) * 4,
            4096
        )

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize
            )
        } catch (e: Exception) {
            sendLog("AudioRecord ошибка: ${e.message}")
            return false
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            sendLog("AudioRecord не инициализирован")
            return false
        }

        audioRecord?.startRecording()
        mode = Mode.LISTENING
        stopRequested = false
        sendToFlutter("onStateChanged", "listening")
        sendLog("Микрофон запущен, жду триггер или PTT...")

        listenerJob = scope.launch {
            mainLoop(bufferSize)
        }

        return true
    }

    private suspend fun mainLoop(bufferSize: Int) {
        val buffer = ShortArray(bufferSize / 2)

        val preTriggerBuffer = mutableListOf<ShortArray>()
        val preTriggerMaxChunks = 8

        val commandBuffer = mutableListOf<ShortArray>()
        var silenceStartTime = 0L
        var speechDetectedInCommand = false
        var lastHighEnergyTime = 0L

        while (mode != Mode.IDLE && !stopRequested) {
            val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
            if (read <= 0) {
                delay(10)
                continue
            }

            val chunk = buffer.copyOf(read)
            val energy = calcEnergy(chunk)

            when (mode) {
                Mode.LISTENING -> {
                    preTriggerBuffer.add(chunk)
                    if (preTriggerBuffer.size > preTriggerMaxChunks) {
                        preTriggerBuffer.removeAt(0)
                    }

                    if (energy > speechThreshold) {
                        lastHighEnergyTime = System.currentTimeMillis()
                    }

                    // ⚠️ ВАЖНО: Здесь ДОЛЖНА быть детекция wake word "Гермес"
                    // Сейчас её НЕТ — только заглушка:
                    // "// Можно добавить детекцию по длительности речи, но пока только PTT"
                }

                Mode.RECORDING -> {
                    commandBuffer.add(chunk)

                    if (energy > silenceThreshold) {
                        speechDetectedInCommand = true
                        silenceStartTime = System.currentTimeMillis()
                    } else if (speechDetectedInCommand && silenceStartTime > 0) {
                        val silenceDuration = System.currentTimeMillis() - silenceStartTime
                        if (silenceDuration >= silenceTimeoutMs && !forcedRecording) {
                            sendLog("Тишина ${silenceDuration}ms, сохраняю...")
                            saveAndSend(preTriggerBuffer, commandBuffer)
                            commandBuffer.clear()
                            preTriggerBuffer.clear()
                            speechDetectedInCommand = false
                            silenceStartTime = 0
                            mode = Mode.LISTENING
                            withContext(Dispatchers.Main) {
                                sendToFlutter("onStateChanged", "listening")
                            }
                        }
                    }

                    // Защита от слишком длинной записи (30 сек)
                    if (commandBuffer.size * buffer.size / SAMPLE_RATE > 30) {
                        sendLog("Запись 30 сек — принудительное сохранение")
                        saveAndSend(preTriggerBuffer, commandBuffer)
                        commandBuffer.clear()
                        preTriggerBuffer.clear()
                        speechDetectedInCommand = false
                        silenceStartTime = 0
                        mode = Mode.LISTENING
                        withContext(Dispatchers.Main) {
                            sendToFlutter("onStateChanged", "listening")
                        }
                    }
                }

                Mode.IDLE -> break
            }
        }
    }

    private suspend fun saveAndSend(
        preTrigger: MutableList<ShortArray>,
        command: MutableList<ShortArray>
    ) {
        val allChunks = preTrigger + command
        val filePath = saveWav(allChunks)
        withContext(Dispatchers.Main) {
            sendToFlutter("onRecordingReady", filePath)
        }
    }

    private fun saveWav(chunks: List<ShortArray>): String {
        val cacheDir = applicationContext.cacheDir
        val file = File(cacheDir, "cmd_${System.currentTimeMillis()}.wav")

        val totalSamples = chunks.sumOf { it.size }
        val dataSize = totalSamples * 2

        FileOutputStream(file).use { fos ->
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray())
            header.putInt(36 + dataSize)
            header.put("WAVE".toByteArray())
            header.put("fmt ".toByteArray())
            header.putInt(16)
            header.putShort(1)
            header.putShort(1)
            header.putInt(SAMPLE_RATE)
            header.putInt(SAMPLE_RATE * 2)
            header.putShort(2)
            header.putShort(16)
            header.put("data".toByteArray())
            header.putInt(dataSize)
            fos.write(header.array())

            for (chunk in chunks) {
                val bytes = ByteArray(chunk.size * 2)
                ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(chunk)
                fos.write(bytes)
            }
        }

        sendLog("WAV сохранён: ${file.name} (${file.length() / 1024} KB)")
        return file.absolutePath
    }

    private fun calcEnergy(samples: ShortArray): Int {
        if (samples.isEmpty()) return 0
        var sum = 0L
        for (s in samples) sum += (s.toLong() * s.toLong())
        return sqrt(sum.toDouble() / samples.size).toInt()
    }

    private fun stopAll() {
        mode = Mode.IDLE
        stopRequested = true
        listenerJob?.cancel()
        listenerJob = null
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
        sendLog("AudioRecord остановлен")
    }

    private fun checkPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
        } else true
    }

    private fun sendToFlutter(method: String, arg: Any?) {
        runOnUiThread {
            methodChannel?.invokeMethod(method, arg)
        }
    }

    private fun sendLog(msg: String) {
        sendToFlutter("onLog", msg)
    }

    override fun onDestroy() {
        stopAll()
        scope.cancel()
        super.onDestroy()
    }
}
```

---

## 7. lib/services/telegram_service.dart (важный — polling в Isolate)

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import '../config.dart';

class _PollParams {
  final String baseUrl;
  final String chatId;
  final SendPort sendPort;
  const _PollParams(this.baseUrl, this.chatId, this.sendPort);
}

class PollEvent {
  final String type;
  final String data;
  const PollEvent(this.type, this.data);
}

@pragma('vm:entry-point')
void _pollingIsolate(_PollParams p) async {
  int lastUpdateId = 0;
  int cycle = 0;
  int errorCount = 0;

  int _backoff(int c) {
    if (c < 5) return 5;
    if (c < 20) return 10;
    if (c < 50) return 30;
    return 60;
  }

  p.sendPort.send(PollEvent('diag', 'Isolate запущен, чат=${p.chatId}'));

  while (true) {
    cycle++;
    try {
      final url = Uri.parse(
        '${p.baseUrl}/getUpdates'
        '?offset=$lastUpdateId'
        '&timeout=25'
        '&allowed_updates=%5B%22message%22%5D',
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 35));

      if (resp.statusCode == 401) {
        p.sendPort.send(PollEvent('error',
            'HTTP 401 — токен бота неверный!'));
        await Future.delayed(const Duration(seconds: 30));
        continue;
      }

      if (resp.statusCode == 409) {
        p.sendPort.send(PollEvent('error',
            'HTTP 409 — конфликт: другой клиент уже читает бота!'));
        await Future.delayed(const Duration(seconds: 30));
        continue;
      }

      if (resp.statusCode != 200) {
        final backoff = _backoff(cycle);
        p.sendPort.send(PollEvent('diag',
            'HTTP ${resp.statusCode}, backoff ${backoff}с (цикл $cycle)'));
        await Future.delayed(Duration(seconds: backoff));
        continue;
      }

      final data = jsonDecode(resp.body);
      if (data['ok'] != true) {
        p.sendPort.send(PollEvent('error', 'ok=false: ${resp.body}'));
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }

      final updates = data['result'] as List;
      if (updates.isNotEmpty) {
        p.sendPort.send(PollEvent('diag', '${updates.length} сообщений'));
      }

      for (final update in updates) {
        lastUpdateId = (update['update_id'] as int) + 1;

        final msg = update['message'];
        if (msg == null) continue;

        final msgChatId = msg['chat']?['id']?.toString() ?? '';
        if (msgChatId != p.chatId) continue;

        if (msg['voice'] != null) {
          final fileId = msg['voice']['file_id'] as String;
          final fileUrl = await _getFileUrl(p.baseUrl, fileId);
          if (fileUrl != null) {
            p.sendPort.send(PollEvent('voice', fileUrl));
          }
        }

        if (msg['audio'] != null) {
          final fileId = msg['audio']['file_id'] as String;
          final fileUrl = await _getFileUrl(p.baseUrl, fileId);
          if (fileUrl != null) {
            p.sendPort.send(PollEvent('voice', fileUrl));
          }
        }

        if (msg['text'] != null) {
          p.sendPort.send(PollEvent('text', msg['text'] as String));
        }
      }
    } catch (e) {
      p.sendPort.send(PollEvent('error', 'Цикл $cycle: $e'));
      await Future.delayed(const Duration(seconds: 5));
    }
  }
}

Future<String?> _getFileUrl(String baseUrl, String fileId) async {
  try {
    final url = Uri.parse('$baseUrl/getFile?file_id=$fileId');
    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    if (data['ok'] != true) return null;
    final filePath = data['result']['file_path'] as String;
    final token = baseUrl.replaceFirst('https://api.telegram.org/bot', '');
    return 'https://api.telegram.org/file/bot$token/$filePath';
  } catch (_) {
    return null;
  }
}

class TelegramService {
  static final TelegramService _i = TelegramService._();
  factory TelegramService() => _i;
  TelegramService._();

  final String _base = 'https://api.telegram.org/bot${Config.botToken}';

  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription? _sub;

  int totalSent = 0;
  int totalFailed = 0;
  DateTime? lastSendTime;

  Function(String url)? onVoiceMessage;
  Function(String text)? onCommand;
  Function(String msg)? onDiag;

  bool get isRunning => _isolate != null;

  Future<void> startListening() async {
    if (_isolate != null) return;
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _pollingIsolate,
      _PollParams(_base, Config.chatId, _receivePort!.sendPort),
    );
    _sub = _receivePort!.listen((msg) {
      if (msg is! PollEvent) return;
      switch (msg.type) {
        case 'voice': onVoiceMessage?.call(msg.data); break;
        case 'text': onCommand?.call(msg.data); break;
        case 'diag': onDiag?.call('[ℹ] ${msg.data}'); break;
        case 'error': onDiag?.call('[❌] ${msg.data}'); break;
      }
    });
    await sendText('✅ Hermes Voice v${Config.appVersion} активирован');
  }

  Future<void> stopListening() async {
    await sendText('⏹ Hermes Voice деактивирован');
    _sub?.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null; _receivePort = null; _sub = null;
  }

  Future<bool> sendVoiceFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        totalFailed++; return false;
      }
      final fileSize = await file.length();
      final ext = filePath.split('.').last.toLowerCase();
      final endpoint = ext == 'ogg' ? 'sendVoice' : 'sendAudio';
      final fieldName = ext == 'ogg' ? 'voice' : 'audio';

      final uri = Uri.parse('$_base/$endpoint');
      final request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = Config.chatId;
      request.files.add(http.MultipartFile(
        fieldName, file.openRead(), fileSize,
        filename: 'voice.$ext',
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      if (streamed.statusCode == 200) {
        totalSent++;
        _cleanupFile(filePath);
        return true;
      }
      return await _sendAsDocument(filePath, file, fileSize);
    } catch (e) {
      totalFailed++; return false;
    }
  }

  Future<bool> _sendAsDocument(String filePath, File file, int fileSize) async {
    try {
      final uri = Uri.parse('$_base/sendDocument');
      final request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = Config.chatId;
      request.files.add(http.MultipartFile(
        'document', file.openRead(), fileSize, filename: 'voice.wav',
      ));
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      if (streamed.statusCode == 200) {
        totalSent++; _cleanupFile(filePath); return true;
      }
      totalFailed++; return false;
    } catch (e) {
      totalFailed++; return false;
    }
  }

  Future<bool> sendText(String text) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/sendMessage'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'chat_id': Config.chatId, 'text': text}),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<String?> checkUpdateUrl() async {
    try {
      final resp = await http.get(Uri.parse(Config.versionCheckUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return resp.body.trim();
    } catch (_) {}
    return null;
  }

  void _cleanupFile(String path) {
    try { File(path).delete(); } catch (_) {}
  }
}
```
