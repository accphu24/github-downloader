import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

/// Lỗi riêng cho trường hợp token hết hạn / bị thu hồi (401),
/// để UI có thể bắt riêng và tự động đăng xuất.
class GithubUnauthorizedException implements Exception {
  final String message;
  GithubUnauthorizedException([this.message = 'Phiên đăng nhập đã hết hạn hoặc bị thu hồi.']);
  @override
  String toString() => message;
}

class GithubFile {
  final String name;
  final String path;
  final String type; // 'file' hoặc 'dir'
  final String? downloadUrl;
  final int? size;

  GithubFile({
    required this.name,
    required this.path,
    required this.type,
    this.downloadUrl,
    this.size,
  });

  factory GithubFile.fromJson(Map<String, dynamic> json) {
    return GithubFile(
      name: json['name'],
      path: json['path'],
      type: json['type'],
      downloadUrl: json['download_url'],
      size: json['size'],
    );
  }

  /// Dùng cho kết quả từ Git Trees API (tìm kiếm toàn repo), không có download_url sẵn.
  factory GithubFile.fromTreeEntry(Map<String, dynamic> json) {
    final path = json['path'] as String;
    return GithubFile(
      name: path.split('/').last,
      path: path,
      type: json['type'] == 'tree' ? 'dir' : 'file',
      size: json['size'],
    );
  }
}

class GithubRepo {
  final String name;
  final String owner;
  final String fullName;
  final bool private;
  final String? description;
  final String defaultBranch;
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
    required this.defaultBranch,
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
      defaultBranch: json['default_branch'] ?? 'main',
      canAdmin: permissions['admin'] == true,
      canPush: permissions['push'] == true,
      canPull: permissions['pull'] == true,
    );
  }
}

/// Phần mở rộng cho các loại file xem trước được dạng text.
const _previewableExtensions = {
  'txt', 'md', 'json', 'yaml', 'yml', 'dart', 'py', 'js', 'ts', 'jsx', 'tsx',
  'html', 'css', 'xml', 'gradle', 'properties', 'gitignore', 'env', 'sh',
  'kt', 'java', 'c', 'cpp', 'h', 'go', 'rs', 'toml', 'ini', 'log', 'csv',
};

bool isPreviewable(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return _previewableExtensions.contains(ext);
}

class WorkflowRun {
  final String name;
  final String status; // queued, in_progress, completed
  final String? conclusion; // success, failure, cancelled, ...
  final String branch;
  final String commitMessage;
  final DateTime createdAt;
  final String htmlUrl;

  WorkflowRun({
    required this.name,
    required this.status,
    required this.branch,
    required this.commitMessage,
    required this.createdAt,
    required this.htmlUrl,
    this.conclusion,
  });

  factory WorkflowRun.fromJson(Map<String, dynamic> json) {
    return WorkflowRun(
      name: json['name'] ?? json['display_title'] ?? 'Workflow',
      status: json['status'] ?? '',
      conclusion: json['conclusion'],
      branch: json['head_branch'] ?? '',
      commitMessage: json['head_commit']?['message'] ?? json['display_title'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      htmlUrl: json['html_url'] ?? '',
    );
  }
}

class GithubCommit {
  final String sha;
  final String message;
  final String authorName;
  final DateTime date;
  final String htmlUrl;

  GithubCommit({
    required this.sha,
    required this.message,
    required this.authorName,
    required this.date,
    required this.htmlUrl,
  });

  factory GithubCommit.fromJson(Map<String, dynamic> json) {
    final commit = json['commit'] ?? {};
    final author = commit['author'] ?? {};
    return GithubCommit(
      sha: json['sha'] ?? '',
      message: commit['message'] ?? '',
      authorName: json['author']?['login'] ?? author['name'] ?? 'Không rõ',
      date: DateTime.parse(author['date'] ?? DateTime.now().toIso8601String()),
      htmlUrl: json['html_url'] ?? '',
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

  void _checkStatus(http.Response response, String contextMessage) {
    if (response.statusCode == 401) {
      throw GithubUnauthorizedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$contextMessage (mã lỗi ${response.statusCode})');
    }
  }

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
      _checkStatus(response, 'Không lấy được danh sách repo');

      final List data = jsonDecode(response.body);
      repos.addAll(data.map((e) => GithubRepo.fromJson(e)));

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
    _checkStatus(response, 'Không lấy được nội dung repo. Repo có thể là private, không tồn tại, hoặc token không đủ quyền.');

    final List data = jsonDecode(response.body);
    return data.map((e) => GithubFile.fromJson(e)).toList();
  }

  /// Lấy thông tin (bao gồm download_url) của đúng 1 file, dùng khi chỉ có path
  /// (ví dụ từ kết quả tìm kiếm toàn repo, chưa có sẵn download_url).
  Future<GithubFile> getFileMeta(String owner, String repo, String path) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path');
    final response = await http.get(url, headers: _headers);
    _checkStatus(response, 'Không lấy được thông tin file');
    return GithubFile.fromJson(jsonDecode(response.body));
  }

  /// Lấy default branch của repo (cần cho tìm kiếm toàn repo qua Git Trees API).
  Future<String> getDefaultBranch(String owner, String repo) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo');
    final response = await http.get(url, headers: _headers);
    _checkStatus(response, 'Không lấy được thông tin repo');
    final data = jsonDecode(response.body);
    return data['default_branch'] ?? 'main';
  }

  /// Tìm kiếm file theo tên/đường dẫn trong TOÀN BỘ repo (mọi thư mục con),
  /// dùng Git Trees API (1 request lấy hết cây thư mục, nhanh hơn nhiều so với
  /// duyệt đệ quy từng thư mục).
  Future<List<GithubFile>> searchFilesInRepo(String owner, String repo, String query) async {
    final branch = await getDefaultBranch(owner, repo);
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/git/trees/$branch', {'recursive': '1'});
    final response = await http.get(url, headers: _headers);
    _checkStatus(response, 'Không tìm kiếm được trong repo');

    final data = jsonDecode(response.body);
    final List tree = data['tree'] ?? [];
    final lowerQuery = query.toLowerCase();

    return tree
        .where((e) => e['type'] == 'blob' && (e['path'] as String).toLowerCase().contains(lowerQuery))
        .map((e) => GithubFile.fromTreeEntry(e))
        .toList();
  }

  Future<List<int>> downloadFile(String downloadUrl) async {
    final response = await http.get(Uri.parse(downloadUrl), headers: _headers);
    _checkStatus(response, 'Tải file thất bại');
    return response.bodyBytes;
  }

  /// Duyệt đệ quy toàn bộ file bên trong 1 thư mục (bao gồm thư mục con).
  /// Public để UI có thể gọi trước nhằm đếm số lượng file (cảnh báo nếu quá nhiều)
  /// trước khi thực sự tải xuống.
  Future<List<GithubFile>> listAllFilesRecursive(String owner, String repo, String path) async {
    final entries = await listContents(owner, repo, path: path);
    final result = <GithubFile>[];
    for (final entry in entries) {
      if (entry.type == 'dir') {
        result.addAll(await listAllFilesRecursive(owner, repo, entry.path));
      } else {
        result.add(entry);
      }
    }
    return result;
  }

  /// Tải danh sách file đã biết trước (từ listAllFilesRecursive) và nén thành zip.
  /// Tách riêng khỏi bước liệt kê để UI có thể đếm số file và cảnh báo trước khi tải.
  Future<List<int>> zipFiles(
    List<GithubFile> files,
    String folderPath, {
    void Function(int done, int total)? onProgress,
  }) async {
    final archive = Archive();

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (file.downloadUrl == null) continue;
      final bytes = await downloadFile(file.downloadUrl!);

      var relativePath = file.path;
      if (folderPath.isNotEmpty && relativePath.startsWith(folderPath)) {
        relativePath = relativePath.substring(folderPath.length);
        if (relativePath.startsWith('/')) relativePath = relativePath.substring(1);
      }

      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      onProgress?.call(i + 1, files.length);
    }

    final zipData = ZipEncoder().encode(archive);
    return zipData ?? [];
  }

  /// Lấy danh sách các lần chạy GitHub Actions gần nhất (build/CI).
  Future<List<WorkflowRun>> listWorkflowRuns(String owner, String repo) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/actions/runs', {'per_page': '30'});
    final response = await http.get(url, headers: _headers);
    _checkStatus(response, 'Không lấy được trạng thái Actions');
    final data = jsonDecode(response.body);
    final List runs = data['workflow_runs'] ?? [];
    return runs.map((e) => WorkflowRun.fromJson(e)).toList();
  }

  /// Lấy lịch sử commit gần nhất của repo.
  Future<List<GithubCommit>> listCommits(String owner, String repo) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/commits', {'per_page': '30'});
    final response = await http.get(url, headers: _headers);
    _checkStatus(response, 'Không lấy được lịch sử commit');
    final List data = jsonDecode(response.body);
    return data.map((e) => GithubCommit.fromJson(e)).toList();
  }

  /// Lấy ngày sửa đổi (commit) gần nhất của 1 file cụ thể.
  /// Lưu ý: mỗi lần gọi tốn 1 request API, nên chỉ dùng khi cần (vd: sort theo ngày).
  Future<DateTime?> getLastCommitDate(String owner, String repo, String path) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/commits', {'path': path, 'per_page': '1'});
    final response = await http.get(url, headers: _headers);
    _checkStatus(response, 'Không lấy được ngày sửa đổi');
    final List data = jsonDecode(response.body);
    if (data.isEmpty) return null;
    final dateStr = data[0]['commit']?['author']?['date'];
    return dateStr != null ? DateTime.parse(dateStr) : null;
  }
}
