import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../l10n/strings.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Tự động bật prompt xác thực ngay khi vào màn hình, khỏi cần bấm thêm 1 lần.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    setState(() {
      _authenticating = true;
      _error = null;
    });
    try {
      final canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canCheck) {
        setState(() => _error = t('lock.not_available'));
        return;
      }
      final success = await _auth.authenticate(
        localizedReason: t('lock.subtitle'),
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (success) {
        widget.onUnlocked();
      } else {
        setState(() => _error = t('lock.failed'));
      }
    } catch (e) {
      setState(() => _error = t('lock.failed'));
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fingerprint_rounded, size: 72, color: scheme.primary),
              const SizedBox(height: 16),
              Text(t('lock.title'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(t('lock.subtitle'), style: TextStyle(color: scheme.onSurfaceVariant)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),
              _authenticating
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _tryUnlock,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: Text(t('lock.unlock_button')),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
