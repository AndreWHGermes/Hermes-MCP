import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// SettingsService — хранит настройки приложения
/// - client_id (UUID) — генерируется при первом запуске
/// - server_url — URL сервера (пользователь может изменить)
/// - is_linked — флаг привязки к пользователю
class SettingsService {
  static final SettingsService _i = SettingsService._();
  factory SettingsService() => _i;
  SettingsService._();

  SharedPreferences? _prefs;

  bool get _ready => _prefs != null;

  Future<void> init() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Client ID (UUID) ────────────────────────────────────────
  String get clientId => _prefs?.getString(Config.prefClientId) ?? '';
  set clientId(String v) => _prefs?.setString(Config.prefClientId, v);

  bool get hasClientId => _prefs?.containsKey(Config.prefClientId) ?? false;

  // ── Server URL ──────────────────────────────────────────────
  String get serverUrl =>
      _prefs?.getString(Config.prefServerUrl) ?? Config.defaultServerUrl;
  set serverUrl(String v) => _prefs?.setString(Config.prefServerUrl, v);

  // ── Is linked ───────────────────────────────────────────────
  bool get isLinked => _prefs?.getBool(Config.prefIsLinked) ?? false;
  set isLinked(bool v) => _prefs?.setBool(Config.prefIsLinked, v);

  // ── Быстрая проверка ────────────────────────────────────────
  Future<bool> checkReady() async {
    if (!_ready) await init();
    return _ready && hasClientId && isLinked;
  }
}
