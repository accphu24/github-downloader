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

class GithubService {
  final String? token;
  GithubService({this.token});

  Map<String, String> get _headers => {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      };

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
