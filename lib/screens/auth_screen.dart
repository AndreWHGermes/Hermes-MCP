import 'dart:async';
import 'package:flutter/material.dart';
import '../services/voice_service.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../config.dart';
import 'home_screen.dart';

// ============================================================
// AuthScreen — экран привязки устройства
// Показывается при первом запуске.
// Генерирует client_id + auth_code (4 цифры).
// После привязки через Telegram — переходит на HomeScreen.
// ============================================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _voice = VoiceService();
  final _settings = SettingsService();

  late String _clientId;
  late String _authCode;
  bool _isLoading = true;
  bool _isChecking = false;
  String? _errorText;
  Timer? _autoCheckTimer;
  Timer? _codeRefreshTimer;

  // Время генерации кода
  late DateTime _codeGeneratedAt;

  @override
  void initState() {
    super.initState();
    _initAuth();
  }

  Future<void> _initAuth() async {
    setState(() => _isLoading = true);

    await _settings.init();

    // Генерируем client_id если нет
    _clientId = await _voice.ensureClientId();

    // Генерируем код
    _authCode = _voice.generateAuthCode();
    _codeGeneratedAt = DateTime.now();

    LogService.info(
      'AuthScreen: client_id=$_clientId, code=$_authCode',
      tag: 'AUTH',
    );

    setState(() => _isLoading = false);

    // Автопроверка каждые 3 секунды
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkStatus();
    });

    // Проверка таймаута кода (5 минут)
    _codeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkCodeExpiry();
    });
  }

  void _checkCodeExpiry() {
    final elapsed = DateTime.now().difference(_codeGeneratedAt);
    if (elapsed.inMinutes >= Config.authCodeTimeoutMinutes) {
      LogService.info('AuthScreen: код устарел, генерирую новый', tag: 'AUTH');
      _generateNewCode();
    }
  }

  void _generateNewCode() {
    setState(() {
      _authCode = _voice.generateAuthCode();
      _codeGeneratedAt = DateTime.now();
      _errorText = null;
    });
  }

  Future<void> _checkStatus() async {
    if (_isChecking || _isLoading) return;
    if (!mounted) return;

    _isChecking = true;

    try {
      final result = await _voice.checkStatus(_clientId);

      if (result['ok'] == true && result['linked'] == true) {
        // Успешно привязаны!
        _autoCheckTimer?.cancel();
        _codeRefreshTimer?.cancel();

        _settings.isLinked = true;

        LogService.success('AuthScreen: привязка подтверждена!', tag: 'AUTH');

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
        return;
      }

      if (result['ok'] == false && result['error'] != null) {
        setState(() {
          _errorText = result['error'] as String;
        });
      } else {
        setState(() => _errorText = null);
      }
    } catch (e) {
      // Тихий провал — сервер может быть недоступен
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _manualCheck() async {
    await _checkStatus();
    if (!mounted) return;
    if (_errorText != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $_errorText'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    _codeRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A8FD1), Color(0xFF1A2535)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        const Spacer(flex: 2),

        // ── Логотип ─────────────────────────────────────────────
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.headset_mic,
            size: 44,
            color: Color(0xFF1A8FD1),
          ),
        ),
        const SizedBox(height: 16),
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
          'Привяжи устройство через Telegram',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),

        const Spacer(flex: 1),

        // ── Код ─────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Text(
                'Твой код:',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              // Крупные 4 цифры
              SelectableText(
                _authCode,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 12,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Напиши /link $_authCode в @GermesMCP_bot',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Ошибка ──────────────────────────────────────────────
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              '⚠️ $_errorText',
              style: const TextStyle(
                color: Color(0xFFFFA726),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        const Spacer(flex: 1),

        // ── Кнопка проверки статуса ─────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _manualCheck,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A8FD1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 4,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Проверить статус',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Статус ──────────────────────────────────────────────
        Text(
          'Автопроверка каждые 3 сек',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),

        // ── ID ──────────────────────────────────────────────────
        const SizedBox(height: 4),
        Text(
          'ID: ${_clientId.length > 12 ? '${_clientId.substring(0, 12)}...' : _clientId}',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}
