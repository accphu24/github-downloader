import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/app_settings.dart';
import 'services/music_service.dart';
import 'screens/login_screen.dart';
import 'screens/repo_list_screen.dart';
import 'widgets/global_download_indicator.dart';

/// Key toàn app để hiện thông báo (vd: "đã tải xong") ngay cả khi tác vụ tải
/// chạy nền hoàn tất lúc người dùng đã chuyển sang màn hình khác.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await AppSettings.instance.load();
    if (AppSettings.instance.musicEnabled && AppSettings.instance.musicUrl.isNotEmpty) {
      await MusicService.instance.play(AppSettings.instance.musicUrl, volume: AppSettings.instance.musicVolume);
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
    return _loggedIn! ? const RepoListScreen() : const LoginScreen();
  }
}
