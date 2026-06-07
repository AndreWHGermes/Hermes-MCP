import 'dart:async';
import 'package:flutter/services.dart';
import 'log_service.dart';

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
        LogService.success('Wake word обнаружен!', tag: 'SPEECH');
        onLog?.call('🎯 Триггер "Гермес" обнаружен!');
        onTriggerDetected?.call();
        break;

      case 'onRecordingReady':
        final path = call.arguments as String?;
        _state = RecorderState.listening;
        onStateChanged?.call(_state);
        if (path != null) {
          onLog?.call('✅ Запись готова: $path');
        }
        onRecordingReady?.call(path ?? '');
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

  Future<bool> startListening({
    String wakeWord = 'Гермес',
    int speechThreshold = 800,
    int silenceThreshold = 300,
    int silenceTimeoutMs = 1500,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startListening', {
        'triggerWord': wakeWord,
        'speechThreshold': speechThreshold,
        'silenceThreshold': silenceThreshold,
        'silenceTimeoutMs': silenceTimeoutMs,
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
