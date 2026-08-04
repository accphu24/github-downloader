import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Trạng thái cài đặt toàn app (giao diện, ngôn ngữ, nhạc nền), tồn tại xuyên suốt
/// vòng đời app và tự lưu lại lâu dài. Dùng ChangeNotifier để mọi màn hình
/// tự động cập nhật khi cài đặt thay đổi.
class AppSettings extends ChangeNotifier {
  static final AppSettings instance = AppSettings._internal();
  AppSettings._internal();

  final _storage = const FlutterSecureStorage();

  double fontScale = 1.0;
  ThemeMode themeMode = ThemeMode.system;
  Color seedColor = const Color(0xFF6C5CE7);
  String locale = 'vi'; // 'vi' hoặc 'en'

  String musicUrl = '';
  bool musicEnabled = false;
  double musicVolume = 0.5;

  bool biometricLockEnabled = false;

  bool _loaded = false;
  bool get loaded => _loaded;

  static const _kFontScale = 'settings_font_scale';
  static const _kThemeMode = 'settings_theme_mode';
  static const _kSeedColor = 'settings_seed_color';
  static const _kLocale = 'settings_locale';
  static const _kMusicUrl = 'settings_music_url';
  static const _kMusicEnabled = 'settings_music_enabled';
  static const _kMusicVolume = 'settings_music_volume';
  static const _kBiometricLock = 'settings_biometric_lock';

  /// Danh sách màu chủ đạo cho người dùng chọn.
  static const presetColors = <Color>[
    Color(0xFF6C5CE7), // tím indigo (mặc định)
    Color(0xFF0984E3), // xanh dương
    Color(0xFF00B894), // xanh lá ngọc
    Color(0xFFE17055), // cam đất
    Color(0xFFD63031), // đỏ
    Color(0xFFE84393), // hồng
  ];

  Future<void> load() async {
    try {
      final fs = await _storage.read(key: _kFontScale);
      if (fs != null) fontScale = double.tryParse(fs) ?? fontScale;

      final tm = await _storage.read(key: _kThemeMode);
      if (tm != null) {
        themeMode = ThemeMode.values.firstWhere((e) => e.name == tm, orElse: () => ThemeMode.system);
      }

      final sc = await _storage.read(key: _kSeedColor);
      if (sc != null) seedColor = Color(int.parse(sc));

      final lc = await _storage.read(key: _kLocale);
      if (lc != null) locale = lc;

      final mu = await _storage.read(key: _kMusicUrl);
      if (mu != null) musicUrl = mu;

      final me = await _storage.read(key: _kMusicEnabled);
      if (me != null) musicEnabled = me == 'true';

      final mv = await _storage.read(key: _kMusicVolume);
      if (mv != null) musicVolume = double.tryParse(mv) ?? musicVolume;

      final bl = await _storage.read(key: _kBiometricLock);
      if (bl != null) biometricLockEnabled = bl == 'true';
    } catch (_) {
      // Nếu đọc lỗi thì dùng giá trị mặc định, không chặn khởi động app.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setFontScale(double value) async {
    fontScale = value;
    await _storage.write(key: _kFontScale, value: value.toString());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _storage.write(key: _kThemeMode, value: mode.name);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    seedColor = color;
    await _storage.write(key: _kSeedColor, value: color.toARGB32().toString());
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    locale = value;
    await _storage.write(key: _kLocale, value: value);
    notifyListeners();
  }

  Future<void> setMusicUrl(String value) async {
    musicUrl = value;
    await _storage.write(key: _kMusicUrl, value: value);
    notifyListeners();
  }

  Future<void> setMusicEnabled(bool value) async {
    musicEnabled = value;
    await _storage.write(key: _kMusicEnabled, value: value.toString());
    notifyListeners();
  }

  Future<void> setMusicVolume(double value) async {
    musicVolume = value;
    await _storage.write(key: _kMusicVolume, value: value.toString());
    notifyListeners();
  }

  Future<void> setBiometricLockEnabled(bool value) async {
    biometricLockEnabled = value;
    await _storage.write(key: _kBiometricLock, value: value.toString());
    notifyListeners();
  }

  /// Dùng cho tính năng xuất/nhập sao lưu (không bao gồm phiên đăng nhập GitHub).
  Map<String, dynamic> toJson() => {
        'fontScale': fontScale,
        'themeMode': themeMode.name,
        'seedColor': seedColor.toARGB32(),
        'locale': locale,
        'musicUrl': musicUrl,
        'musicEnabled': musicEnabled,
        'musicVolume': musicVolume,
        'biometricLockEnabled': biometricLockEnabled,
      };

  Future<void> applyJson(Map<String, dynamic> json) async {
    if (json['fontScale'] is num) await setFontScale((json['fontScale'] as num).toDouble());
    if (json['themeMode'] is String) {
      await setThemeMode(ThemeMode.values.firstWhere((e) => e.name == json['themeMode'], orElse: () => ThemeMode.system));
    }
    if (json['seedColor'] is int) await setSeedColor(Color(json['seedColor'] as int));
    if (json['locale'] is String) await setLocale(json['locale'] as String);
    if (json['musicUrl'] is String) await setMusicUrl(json['musicUrl'] as String);
    if (json['musicEnabled'] is bool) await setMusicEnabled(json['musicEnabled'] as bool);
    if (json['musicVolume'] is num) await setMusicVolume((json['musicVolume'] as num).toDouble());
    if (json['biometricLockEnabled'] is bool) await setBiometricLockEnabled(json['biometricLockEnabled'] as bool);
  }
}
