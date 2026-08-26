import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_settings.dart';
import '../services/music_service.dart';
import '../services/pinned_repos_service.dart';
import '../services/downloads_service.dart';
import '../services/log_service.dart';
import '../services/ci_watch_service.dart';
import '../l10n/strings.dart';
import '../widgets/top_notification.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _musicUrlController;
  final _pinnedService = PinnedReposService();
  int _pinnedCount = 0;

  @override
  void initState() {
    super.initState();
    _musicUrlController = TextEditingController(text: AppSettings.instance.musicUrl);
    _pinnedService.getPinned().then((p) {
      if (mounted) setState(() => _pinnedCount = p.length);
    });
  }

  @override
  void dispose() {
    _musicUrlController.dispose();
    super.dispose();
  }

  Future<void> _exportBackup() async {
    final pinned = await _pinnedService.getPinned();
    final backup = {
      'settings': AppSettings.instance.toJson(),
      'pinnedRepos': pinned.toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);
    final savedPath = await DownloadsService.saveBytes('github_downloader_backup.json', utf8.encode(jsonStr));
    if (mounted && savedPath != null) {
      showTopNotification(context, t('settings.backup_export_success', {'path': savedPath}));
    }
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;

    try {
      final jsonStr = utf8.decode(bytes);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (data['settings'] is Map<String, dynamic>) {
        await AppSettings.instance.applyJson(data['settings'] as Map<String, dynamic>);
      }
      if (data['pinnedRepos'] is List) {
        await _pinnedService.setAll((data['pinnedRepos'] as List).map((e) => e.toString()).toList());
        // Danh sách ghim vừa đổi (có thể khác hẳn trước) - nếu đang bật theo dõi
        // CI/CD nền thì phải đồng bộ lại ngay, nếu không service nền vẫn tiếp tục
        // theo dõi danh sách repo CŨ cho tới khi tắt/bật lại thủ công.
        await CiWatchService.instance.syncWatchedReposIfEnabled();
      }

      final pinnedCount = (await _pinnedService.getPinned()).length;
      _musicUrlController.text = AppSettings.instance.musicUrl;
      if (mounted) {
        showTopNotification(context, t('settings.backup_import_success'));
        setState(() => _pinnedCount = pinnedCount);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('settings.backup_import_error'))));
      }
    }
  }

  Future<void> _exportLogNow() async {
    final path = await LogService.instance.saveToDevice(force: true);
    if (!mounted) return;
    if (path != null) {
      showTopNotification(context, t('settings.log_export_success', {'path': path}));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('settings.log_export_empty'))));
    }
  }

  void _clearLog() {
    LogService.instance.clear();
    showTopNotification(context, t('settings.log_cleared'));
  }

  Future<void> _toggleCiWatch(bool value) async {
    if (!value) {
      await CiWatchService.instance.disable();
      return;
    }
    final ok = await CiWatchService.instance.enable();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('settings.ci_watch_no_pins'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge([settings, LogService.instance]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(t('settings.title'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle(context, t('settings.section_appearance')),
              const SizedBox(height: 8),
              Card(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('settings.font_size'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          const Text('A', style: TextStyle(fontSize: 14)),
                          Expanded(
                            child: Slider(
                              value: settings.fontScale,
                              min: 0.8,
                              max: 1.4,
                              divisions: 6,
                              label: '${(settings.fontScale * 100).round()}%',
                              onChanged: (v) => settings.setFontScale(v),
                            ),
                          ),
                          const Text('A', style: TextStyle(fontSize: 22)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(t('settings.theme_mode'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(value: ThemeMode.system, label: Text(t('settings.theme_system'))),
                          ButtonSegment(value: ThemeMode.light, label: Text(t('settings.theme_light'))),
                          ButtonSegment(value: ThemeMode.dark, label: Text(t('settings.theme_dark'))),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (s) => settings.setThemeMode(s.first),
                      ),
                      const SizedBox(height: 16),
                      Text(t('settings.accent_color'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        children: AppSettings.presetColors.map((color) {
                          final selected = settings.seedColor.toARGB32() == color.toARGB32();
                          return GestureDetector(
                            onTap: () => settings.setSeedColor(color),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: selected ? Border.all(color: scheme.onSurface, width: 3) : null,
                              ),
                              child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, t('settings.section_music')),
              const SizedBox(height: 8),
              Card(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('settings.music_enable')),
                        value: settings.musicEnabled,
                        onChanged: (v) async {
                          await settings.setMusicEnabled(v);
                          if (v) {
                            await MusicService.instance.play(settings.musicUrl, volume: settings.musicVolume);
                          } else {
                            await MusicService.instance.pause();
                          }
                        },
                      ),
                      TextField(
                        controller: _musicUrlController,
                        decoration: InputDecoration(
                          labelText: t('settings.music_url_label'),
                          hintText: t('settings.music_url_hint'),
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (v) => settings.setMusicUrl(v),
                        onEditingComplete: () => settings.setMusicUrl(_musicUrlController.text),
                      ),
                      const SizedBox(height: 12),
                      Text(t('settings.music_volume'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          const Icon(Icons.volume_down_rounded),
                          Expanded(
                            child: Slider(
                              value: settings.musicVolume,
                              onChanged: (v) {
                                settings.setMusicVolume(v);
                                MusicService.instance.setVolume(v);
                              },
                            ),
                          ),
                          const Icon(Icons.volume_up_rounded),
                        ],
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(MusicService.instance.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          label: Text(MusicService.instance.isPlaying ? t('settings.music_pause') : t('settings.music_play')),
                          onPressed: () async {
                            await settings.setMusicUrl(_musicUrlController.text);
                            if (MusicService.instance.isPlaying) {
                              await MusicService.instance.pause();
                            } else {
                              await MusicService.instance.play(_musicUrlController.text, volume: settings.musicVolume);
                            }
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, t('settings.section_language')),
              const SizedBox(height: 8),
              Card(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: Text(t('settings.language_vi')),
                      value: 'vi',
                      groupValue: settings.locale,
                      onChanged: (v) => settings.setLocale(v!),
                    ),
                    RadioListTile<String>(
                      title: Text(t('settings.language_en')),
                      value: 'en',
                      groupValue: settings.locale,
                      onChanged: (v) => settings.setLocale(v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, t('settings.section_security')),
              const SizedBox(height: 8),
              Card(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: SwitchListTile(
                  title: Text(t('settings.biometric_lock')),
                  secondary: const Icon(Icons.fingerprint_rounded),
                  value: settings.biometricLockEnabled,
                  onChanged: (v) => settings.setBiometricLockEnabled(v),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, t('settings.section_ci_watch')),
              const SizedBox(height: 8),
              Card(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('settings.ci_watch_enable')),
                        secondary: const Icon(Icons.notifications_active_rounded),
                        value: settings.ciWatchEnabled,
                        onChanged: _toggleCiWatch,
                      ),
                      Text(
                        _pinnedCount > 0 ? t('settings.ci_watch_hint', {'count': '$_pinnedCount'}) : t('settings.ci_watch_no_pins'),
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, t('settings.section_backup')),
              const SizedBox(height: 8),
              Card(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.upload_rounded),
                              label: Text(t('settings.backup_export')),
                              onPressed: _exportBackup,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.download_rounded),
                              label: Text(t('settings.backup_import')),
                              onPressed: _importBackup,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('settings.backup_note'),
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(context, t('settings.section_log')),
              const SizedBox(height: 8),
              Card(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('settings.log_enable')),
                        secondary: const Icon(Icons.bug_report_outlined),
                        value: settings.detailedLogEnabled,
                        onChanged: (v) => settings.setDetailedLogEnabled(v),
                      ),
                      Text(
                        t('settings.log_enable_hint'),
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t('settings.log_auto_save_hint'),
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t('settings.log_entry_count', {'count': '${LogService.instance.entries.length}'}),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.download_rounded),
                              label: Text(t('settings.log_export_now')),
                              onPressed: settings.detailedLogEnabled ? _exportLogNow : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: Text(t('settings.log_clear')),
                              onPressed: LogService.instance.entries.isEmpty ? null : _clearLog,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
