import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/auth_service.dart';
import 'services/app_settings.dart';
import 'services/music_service.dart';
import 'services/log_service.dart';
import 'services/keep_alive_service.dart';
import 'screens/login_screen.dart';
import 'screens/repo_list_screen.dart';
import 'screens/lock_screen.dart';
import 'widgets/global_download_indicator.dart';

/// Key toàn app để hiện thông báo (vd: "đã tải xong") ngay cả khi tác vụ tải
/// chạy nền hoàn tất lúc người dùng đã chuyển sang màn hình khác.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // Bắt buộc gọi trước runApp() để flutter_foreground_task có thể giao tiếp
  // giữa isolate của foreground service và app chính.
  FlutterForegroundTask.initCommunicationPort();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await AppSettings.instance.load();
    KeepAliveService.instance.init();
    LogService.instance.info('App khởi động');
    if (AppSettings.instance.musicEnabled && AppSettings.instance.musicUrl.isNotEmpty) {
      await MusicService.instance.play(AppSettings.instance.musicUrl, volume: AppSettings.instance.musicVolume);
    }
  }

  /// Mobile không có sự kiện "đóng app" đáng tin cậy (khi hệ điều hành giết
  /// tiến trình, code Dart không kịp chạy). Cách thực tế nhất là tự lưu file
  /// log ngay khi app bị ẩn xuống nền (paused) hoặc thoát hẳn (detached) -
  /// đây chính là thời điểm người dùng "đóng app" theo thao tác thông thường
  /// (bấm nút Home, vuốt khỏi Recent Apps, chuyển app khác...).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!AppSettings.instance.detailedLogEnabled) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      LogService.instance.info('App chuyển sang nền/đóng (${state.name}) - tự lưu log');
      LogService.instance.saveToDevice();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;

        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'GitHub Repo Downloader',
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: settings.seedColor,
            brightness: Brightness.light,
            appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            chipTheme: ChipThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: settings.seedColor,
            brightness: Brightness.dark,
            appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          themeMode: settings.themeMode,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: TextScaler.linear(settings.fontScale)),
              child: Stack(
                children: [
                  child!,
                  const GlobalDownloadIndicator(),
                ],
              ),
            );
          },
          home: _StartupGate(),
        );
      },
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  final _authService = AuthService();
  bool? _loggedIn;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final loggedIn = await _authService.isLoggedIn();
    if (mounted) setState(() => _loggedIn = loggedIn);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null || !AppSettings.instance.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_loggedIn!) return const LoginScreen();

    if (AppSettings.instance.biometricLockEnabled && !_unlocked) {
      return LockScreen(onUnlocked: () => setState(() => _unlocked = true));
    }

    return const RepoListScreen();
  }
}
