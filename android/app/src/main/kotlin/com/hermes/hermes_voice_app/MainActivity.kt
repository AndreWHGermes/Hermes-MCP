package com.hermes.hermes_voice_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

// ============================================================
// HERMES VOICE APP — MainActivity v6.3
//
//  Wake word: Google SpeechRecognizer (встроенный, офлайн)
//  Запись: AudioRecord → PCM → WAV
//  Установка APK: FileProvider + ACTION_VIEW Intent
// ============================================================

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.hermes.voice/recorder"
        private const val CHANNEL_INSTALLER = "com.hermes.voice/installer"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val MAX_RECORD_SECONDS = 10
    }

    // ── Flutter channel
    private var methodChannel: MethodChannel? = null

    // ── Google SpeechRecognizer (wake word detection)
    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening = false
    private var shouldRestart = false
    private var restartDelayMs = 100L

    // ── Anti-flood: не срабатывать повторно в течение 3 сек
    private var lastWakeMs = 0L
    private val WAKE_COOLDOWN_MS = 3000L

    // ── AudioRecord (запись команды после wake word)
    private var audioRecord: AudioRecord? = null
    private var recordingJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ── AudioManager (AudioFocus)
    private lateinit var audioManager: AudioManager

    // ── Состояние
    enum class Mode { IDLE, WAITING, RECORDING }
    @Volatile private var mode = Mode.IDLE
    @Volatile private var active = false

    // ══════════════════════════════════════════════════════════
    // Flutter Engine Setup
    // ══════════════════════════════════════════════════════════

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(AudioManager::class.java)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {

                "startListening" -> {
                    val ok = startListening()
                    result.success(ok)
                }

                "stopListening" -> {
                    stopAll()
                    result.success(null)
                }

                "forceStartRecording" -> {
                    // При PTT триггерим запись вручную
                    if (mode == Mode.WAITING) {
                        startRecordingCommand()
                    }
                    result.success(null)
                }

                "forceStopRecording" -> {
                    finishRecording()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // ── Installer Channel (для автообновления) ──────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_INSTALLER
        ).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val apkPath = call.argument<String>("apkPath") ?: ""
                val ok = installApk(apkPath)
                result.success(ok)
            } else {
                result.notImplemented()
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // W A K E   W O R D   D E T E C T I O N
    // Google SpeechRecognizer — слушает в цикле фразу "гермес"
    // ══════════════════════════════════════════════════════════

    private fun startListening(): Boolean {
        if (!checkPermission()) {
            sendLog("❌ Нет разрешения RECORD_AUDIO")
            return false
        }

        stopAll()
        active = true
        shouldRestart = true
        mode = Mode.WAITING

        startSpeechRecognition()
        return true
    }

    private fun startSpeechRecognition() {
        if (!active || !shouldRestart) return

        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }

        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}

            override fun onError(error: Int) {
                val errName = when (error) {
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Timeout"
                    SpeechRecognizer.ERROR_NETWORK -> "Network"
                    SpeechRecognizer.ERROR_AUDIO -> "Audio"
                    SpeechRecognizer.ERROR_SERVER -> "Server"
                    SpeechRecognizer.ERROR_CLIENT -> "Client"
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "SpeechTimeout"
                    SpeechRecognizer.ERROR_NO_MATCH -> "NoMatch"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Busy"
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "NoPermission"
                    SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "TooMany"
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "LangNotSupported"
                    SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "LangUnavail"
                    else -> "Err#$error"
                }
                if (error != SpeechRecognizer.ERROR_NO_MATCH &&
                    error != SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                    sendLog("⚠️ SR: $errName")
                }
                // Плавный backoff: увеличиваем задержку при частых ошибках, сбрасываем при успехе
                if (active && shouldRestart) {
                    val delay = when (error) {
                        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> 5000L
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 2000L
                        SpeechRecognizer.ERROR_NETWORK -> 3000L
                        SpeechRecognizer.ERROR_SERVER -> 2000L
                        else -> {
                            // Постепенно увеличиваем до 2 сек
                            restartDelayMs = minOf(restartDelayMs * 2, 2000L)
                            restartDelayMs
                        }
                    }
                    Handler(mainLooper).postDelayed({
                        startSpeechRecognition()
                    }, delay)
                }
            }

            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (matches != null && matches.isNotEmpty()) {
                    val text = matches[0].lowercase()
                    checkWakeWord(text)
                }
                // Сброс backoff при успешном результате
                restartDelayMs = 100L
                if (active && shouldRestart) {
                    Handler(mainLooper).postDelayed({
                        startSpeechRecognition()
                    }, 200L)
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (matches != null && matches.isNotEmpty()) {
                    val text = matches[0].lowercase()
                    checkWakeWord(text)
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        speechRecognizer?.startListening(intent)
        if (!isListening) {
            isListening = true
            mode = Mode.WAITING
            sendToFlutter("onStateChanged", "listening")
            sendLog("🎙 Жду \"гермес\"...")
        }
    }

    private fun checkWakeWord(text: String) {
        val now = System.currentTimeMillis()
        // Anti-flood: игнорируем повторные срабатывания в течение WAKE_COOLDOWN_MS
        if (now - lastWakeMs < WAKE_COOLDOWN_MS) return
        if (mode != Mode.WAITING) return

        val hasWake = text.contains("гермес") || text.contains("гермез") ||
                      text.contains("гермэс") || text.contains("hermes") ||
                      text.contains("гермис")

        if (hasWake) {
            lastWakeMs = now
            sendLog("🎯 Wake word 'Гермес' обнаружен!")
            sendToFlutter("onTriggerDetected", null)
            startRecordingCommand()
        }
    }

    // ══════════════════════════════════════════════════════════
    // З А П И С Ь   К О М А Н Д Ы
    // AudioRecord → PCM файл → WAV конвертация
    // ══════════════════════════════════════════════════════════

    private fun startRecordingCommand() {
        mode = Mode.RECORDING
        sendToFlutter("onStateChanged", "recording")
        sendLog("🔴 Записываю команду...")

        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        val bufferSize = maxOf(minBuf * 2, 2560)

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize
            )
        } catch (e: Exception) {
            sendLog("❌ AudioRecord ошибка: ${e.message}")
            mode = Mode.WAITING
            return
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            sendLog("❌ AudioRecord не инициализирован")
            mode = Mode.WAITING
            return
        }

        audioRecord?.startRecording()

        recordingJob = scope.launch {
            recordToFile(bufferSize)
        }
    }

    private suspend fun recordToFile(bufferSize: Int) {
        val buffer = ShortArray(bufferSize / 2)
        val cmdFile = File(applicationContext.cacheDir, "cmd_${System.currentTimeMillis()}.pcm")
        var fos: FileOutputStream? = null
        var totalSamples = 0

        try {
            fos = FileOutputStream(cmdFile)
        } catch (e: Exception) {
            sendLog("❌ Не могу создать файл записи: ${e.message}")
            mode = Mode.WAITING
            return
        }

        var silenceMs = 0L
        var hadSpeech = false
        val maxSamples = SAMPLE_RATE * MAX_RECORD_SECONDS

        while (mode == Mode.RECORDING && totalSamples < maxSamples) {
            val read = try {
                audioRecord?.read(buffer, 0, buffer.size) ?: -1
            } catch (e: Exception) {
                -1
            }
            if (read <= 0) {
                delay(10)
                continue
            }

            val chunk = buffer.copyOf(read)
            val energy = calcEnergy(chunk)

            // Записываем в файл
            val bytes = ByteArray(chunk.size * 2)
            ByteBuffer.wrap(bytes)
                .order(ByteOrder.LITTLE_ENDIAN)
                .asShortBuffer()
                .put(chunk)
            fos?.write(bytes)
            totalSamples += chunk.size

            // Детекция тишины для автоостановки
            if (energy > 800) {
                hadSpeech = true
                silenceMs = System.currentTimeMillis()
            } else if (hadSpeech && System.currentTimeMillis() - silenceMs > 2000) {
                // Тишина 2 секунды после речи — сохраняем
                break
            }
        }

        try { fos?.flush(); fos?.close() } catch (_: Exception) {}

        // Конвертируем PCM → WAV
        val wavFile = pcmToWav(cmdFile, totalSamples)
        try { cmdFile.delete() } catch (_: Exception) {}

        if (wavFile != null) {
            sendLog("✅ Команда записана: ${wavFile.absolutePath}")
            sendToFlutter("onRecordingReady", wavFile.absolutePath)
        } else {
            sendLog("❌ Ошибка конвертации PCM→WAV")
        }

        // Возвращаемся в режим слушания
        mode = Mode.WAITING
        sendToFlutter("onStateChanged", "listening")
        sendLog("🎙 Снова жду \"гермес\"...")
    }

    private fun finishRecording() {
        recordingJob?.cancel()
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
        mode = Mode.WAITING
        sendToFlutter("onStateChanged", "listening")
    }

    private fun pcmToWav(pcmFile: File, totalSamples: Int): File? {
        return try {
            val dataSize = totalSamples * 2
            val wavFile = File(applicationContext.cacheDir, pcmFile.nameWithoutExtension + ".wav")

            FileOutputStream(wavFile).use { fos ->
                val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
                header.put("RIFF".toByteArray())
                header.putInt(36 + dataSize)
                header.put("WAVE".toByteArray())
                header.put("fmt ".toByteArray())
                header.putInt(16)
                header.putShort(1)  // PCM
                header.putShort(1)  // Mono
                header.putInt(SAMPLE_RATE)
                header.putInt(SAMPLE_RATE * 2)  // byte rate
                header.putShort(2)  // block align
                header.putShort(16) // bits per sample
                header.put("data".toByteArray())
                header.putInt(dataSize)
                fos.write(header.array())

                pcmFile.inputStream().use { it.copyTo(fos) }
            }
            wavFile
        } catch (e: Exception) {
            sendLog("PCM→WAV ошибка: ${e.message}")
            null
        }
    }

    private fun calcEnergy(samples: ShortArray): Double {
        var sum = 0.0
        for (s in samples) sum += s.toDouble() * s.toDouble()
        return sqrt(sum / samples.size)
    }

    // ══════════════════════════════════════════════════════════
    // Установка APK (через FileProvider для Android 7+)
    // ══════════════════════════════════════════════════════════

    private fun installApk(apkPath: String): Boolean {
        return try {
            val apkFile = File(apkPath)
            if (!apkFile.exists()) {
                sendLog("❌ APK не найден: $apkPath")
                return false
            }

            val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Android 7+ (API 25+): используем FileProvider → content:// URI
                FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    apkFile
                )
            } else {
                Uri.fromFile(apkFile)
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // Для Android 10+ (API 29+)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }

            startActivity(intent)
            sendLog("🔄 Запущена установка APK...")
            true
        } catch (e: Exception) {
            sendLog("❌ Ошибка установки APK: ${e.message}")
            false
        }
    }

    // ══════════════════════════════════════════════════════════
    // Утилиты
    // ══════════════════════════════════════════════════════════

    private fun stopAll() {
        active = false
        shouldRestart = false
        isListening = false
        mode = Mode.IDLE

        recordingJob?.cancel()
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null

        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null

        sendLog("🔴 Выключен")
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
        super.onDestroy()
    }
}
