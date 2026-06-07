import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    _urlController.text = _settings.serverUrl;
  }

  void _saveUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL не может быть пустым')),
      );
      return;
    }
    _settings.serverUrl = url;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ URL сохранён'),
        backgroundColor: Color(0xFF2ECC71),
      ),
    );
  }

  void _resetUrl() {
    _urlController.text = Config.defaultServerUrl;
    _settings.serverUrl = Config.defaultServerUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ URL сброшен на стандартный'),
        backgroundColor: Color(0xFF2ECC71),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── URL сервера ──
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.dns, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Сервер', style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL сервера',
                      hintText: 'https://gptconnect.tw1.ru',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saveUrl,
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text('Сохранить'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _resetUrl,
                        child: const Text('Сбросить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Информация ──
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Приложение', style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Hermes Voice v${Config.appVersion}\n'
                    'Wake word: Гермес\n'
                    'Связь напрямую с сервером (без Telegram API)',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
