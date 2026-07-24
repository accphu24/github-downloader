import 'dart:convert';
import 'package:http/http.dart' as http;

class GithubFile {
  final String name;
  final String path;
  final String type; // 'file' hoặc 'dir'
  final String? downloadUrl;

  GithubFile({
    required this.name,
    required this.path,
    required this.type,
    this.downloadUrl,
  });

  factory GithubFile.fromJson(Map<String, dynamic> json) {
    return GithubFile(
      name: json['name'],
      path: json['path'],
      type: json['type'],
      downloadUrl: json['download_url'],
    );
  }
}

class GithubRepo {
  final String name;
  final String owner;
  final String fullName;
  final bool private;
  final String? description;
  final bool canAdmin;
  final bool canPush;
  final bool canPull;

  GithubRepo({
    required this.name,
    required this.owner,
    required this.fullName,
    required this.private,
    required this.canAdmin,
    required this.canPush,
    required this.canPull,
    this.description,
  });

  /// Mô tả quyền hạn dạng dễ hiểu để hiển thị lên UI.
  String get permissionLabel {
    if (canAdmin) return 'Admin';
    if (canPush) return 'Ghi (Write)';
    if (canPull) return 'Chỉ đọc (Read-only)';
    return 'Không rõ';
  }

  factory GithubRepo.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'] as Map<String, dynamic>? ?? {};
    return GithubRepo(
      name: json['name'],
      owner: json['owner']?['login'] ?? '',
      fullName: json['full_name'] ?? '',
      private: json['private'] ?? false,
      description: json['description'],
      canAdmin: permissions['admin'] == true,
      canPush: permissions['push'] == true,
      canPull: permissions['pull'] == true,
    );
  }
}

class GithubService {
  final String? token;
  GithubService({this.token});

  Map<String, String> get _headers => {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      };

  /// Liệt kê TẤT CẢ repo mà tài khoản đang đăng nhập có quyền truy cập
  /// (sở hữu, được thêm làm collaborator, hoặc thuộc tổ chức), kèm quyền hạn cụ thể.
  /// Tự động lấy hết các trang (phân trang) qua header 'Link' của GitHub.
  Future<List<GithubRepo>> listUserRepos() async {
    final repos = <GithubRepo>[];
    Uri? url = Uri.https('api.github.com', '/user/repos', {
      'per_page': '100',
      'sort': 'updated',
      'affiliation': 'owner,collaborator,organization_member',
    });

    while (url != null) {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode != 200) {
        throw Exception('Không lấy được danh sách repo (mã lỗi ${response.statusCode}). Kiểm tra lại đăng nhập.');
      }

      final List data = jsonDecode(response.body);
      repos.addAll(data.map((e) => GithubRepo.fromJson(e)));

      // Xử lý phân trang qua header Link: <url>; rel="next"
      url = null;
      final linkHeader = response.headers['link'];
      if (linkHeader != null) {
        final parts = linkHeader.split(',');
        for (final part in parts) {
          if (part.contains('rel="next"')) {
            final match = RegExp(r'<(.*)>').firstMatch(part);
            if (match != null) url = Uri.parse(match.group(1)!);
          }
        }
      }
    }

    return repos;
  }

  /// Liệt kê file/thư mục trong repo tại 1 path cụ thể.
  /// Repo public không cần token, repo private cần token có scope 'repo'.
  Future<List<GithubFile>> listContents(String owner, String repo, {String path = ''}) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path');
    final response = await http.get(url, headers: _headers);

    if (response.statusCode != 200) {
      throw Exception(
        'Không lấy được nội dung repo (mã lỗi ${response.statusCode}). '
        'Repo có thể là private, không tồn tại, hoặc token không đủ quyền.',
      );
    }

    final List data = jsonDecode(response.body);
    return data.map((e) => GithubFile.fromJson(e)).toList();
  }

  Future<List<int>> downloadFile(String downloadUrl) async {
    final response = await http.get(Uri.parse(downloadUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Tải file thất bại (mã lỗi ${response.statusCode})');
    }
    return response.bodyBytes;
  }
}
