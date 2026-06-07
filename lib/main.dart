import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/home_screen.dart';
import 'screens/auth_screen.dart';
import 'services/log_service.dart';
import 'services/settings_service.dart';
import 'services/voice_service.dart';

// Top-level — ОБЯЗАТЕЛЬНО для flutter_background_service
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
  await LogService().init();
  await SettingsService().init();
  LogService.info('Приложение запущено v7.0.0', tag: 'MAIN');

  // Генерируем client_id при первом запуске
  await VoiceService().ensureClientId();

  await _initBackgroundService();

  // Определяем, показывать ли экран привязки
  final isLinked = SettingsService().isLinked;
  LogService.info('MAIN: isLinked=$isLinked', tag: 'MAIN');

  runApp(HermesVoiceApp(initialLinked: isLinked));
}

class HermesVoiceApp extends StatelessWidget {
  final bool initialLinked;

  const HermesVoiceApp({super.key, required this.initialLinked});

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
      home: initialLinked ? const HomeScreen() : const AuthScreen(),
    );
  }
}
