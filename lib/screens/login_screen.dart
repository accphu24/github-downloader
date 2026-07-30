import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../l10n/strings.dart';
import 'repo_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  bool _loading = false;

  Future<void> _handleLogin() async {
    setState(() => _loading = true);
    final error = await _authService.login();
    if (!mounted) return;
    setState(() => _loading = false);

    if (error == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RepoListScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 10)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer.withValues(alpha: 0.6), scheme.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Icon(Icons.code_rounded, size: 48, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t('login.title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('login.subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: _handleLogin,
                            icon: const Icon(Icons.login_rounded),
                            label: Text(t('login.button')),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
