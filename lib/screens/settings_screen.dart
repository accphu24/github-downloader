import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/music_service.dart';
import '../l10n/strings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _musicUrlController;

  @override
  void initState() {
    super.initState();
    _musicUrlController = TextEditingController(text: AppSettings.instance.musicUrl);
  }

  @override
  void dispose() {
    _musicUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: settings,
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
