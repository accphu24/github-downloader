import 'dart:convert';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  // TODO: thay bằng Client ID thật lấy từ GitHub OAuth App
  static const String clientId = 'Ov23ct4O7d9Fv0KW1kC8';

  // TODO: thay bằng URL backend Railway của bạn (không có dấu "/" ở cuối)
  static const String backendUrl = 'https://your-backend.up.railway.app';

  static const String callbackScheme = 'githubdownloader';
  static const String redirectUri = '$callbackScheme://callback';

  final _storage = const FlutterSecureStorage();

  /// Mở trình duyệt để user đăng nhập GitHub, sau đó đổi code lấy access token
  /// thông qua backend (client_secret không bao giờ nằm trong app).
  Future<bool> login() async {
    final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': 'repo user:email',
    });

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: callbackScheme,
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) return false;

      final response = await http.post(
        Uri.parse('$backendUrl/oauth/callback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final token = data['access_token'];
      if (token == null) return false;

      await _storage.write(key: 'github_token', value: token);

      // Lấy username + email thật từ GitHub, khỏi cần user tự nhập
      final userInfo = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (userInfo.statusCode == 200) {
        final user = jsonDecode(userInfo.body);
        await _storage.write(key: 'github_username', value: user['login'] ?? '');
        await _storage.write(key: 'github_email', value: user['email'] ?? '');
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getToken() => _storage.read(key: 'github_token');
  Future<String?> getUsername() => _storage.read(key: 'github_username');
  Future<String?> getEmail() => _storage.read(key: 'github_email');

  Future<bool> isLoggedIn() async => (await getToken()) != null;

  Future<void> logout() async => _storage.deleteAll();
}
