import 'dart:convert';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const String clientId = 'Ov23ct4O7d9Fv0KW1kC8';

  static const String backendUrl = 'https://web-production-0522b.up.railway.app';

  static const String callbackScheme = 'githubdownloader';
  static const String redirectUri = '$callbackScheme://callback';

  final _storage = const FlutterSecureStorage();

  /// Mở trình duyệt để user đăng nhập GitHub, sau đó đổi code lấy access token
  /// thông qua backend (client_secret không bao giờ nằm trong app).
  /// Trả về null nếu thành công, hoặc chuỗi mô tả lỗi nếu thất bại.
  Future<String?> login() async {
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
      if (code == null) return 'Không nhận được mã code từ GitHub (url: $result)';

      final response = await http.post(
        Uri.parse('$backendUrl/oauth/callback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );

      if (response.statusCode != 200) {
        return 'Backend lỗi ${response.statusCode}: ${response.body}';
      }

      final data = jsonDecode(response.body);
      final token = data['access_token'];
      if (token == null) return 'Backend không trả về access_token: ${response.body}';

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

      return null;
    } catch (e) {
      return 'Lỗi: $e';
    }
  }

  Future<String?> getToken() => _storage.read(key: 'github_token');
  Future<String?> getUsername() => _storage.read(key: 'github_username');
  Future<String?> getEmail() => _storage.read(key: 'github_email');

  Future<bool> isLoggedIn() async => (await getToken()) != null;

  Future<void> logout() async => _storage.deleteAll();
}
