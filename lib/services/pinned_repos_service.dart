import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lưu danh sách repo được ghim (favorite) để hiện lên đầu danh sách,
/// giúp mở nhanh những repo hay dùng nhất.
class PinnedReposService {
  static const _key = 'pinned_repos';
  final _storage = const FlutterSecureStorage();

  Future<Set<String>> getPinned() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return {};
    return Set<String>.from(jsonDecode(raw));
  }

  Future<Set<String>> togglePin(String fullName) async {
    final pinned = await getPinned();
    if (pinned.contains(fullName)) {
      pinned.remove(fullName);
    } else {
      pinned.add(fullName);
    }
    await _storage.write(key: _key, value: jsonEncode(pinned.toList()));
    return pinned;
  }
}
