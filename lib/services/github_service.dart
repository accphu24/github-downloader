import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'log_service.dart';

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
  final String? sha;

  GithubFile({
    required this.name,
    required this.path,
    required this.type,
    this.downloadUrl,
    this.size,
    this.sha,
  });

  factory GithubFile.fromJson(Map<String, dynamic> json) {
    return GithubFile(
      name: json['name'],
      path: json['path'],
      type: json['type'],
      downloadUrl: json['download_url'],
      size: json['size'],
      sha: json['sha'],
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

/// 1 thông báo từ GitHub (mention, review request, CI cập nhật, v.v).
class GithubNotification {
  final String id;
  final String repoFullName;
  final String subjectTitle;
  final String subjectType; // Issue, PullRequest, Commit, Release, Discussion, CheckSuite...
  final String reason;
  bool unread; // không final: UI tự cập nhật cục bộ ngay khi đánh dấu đã đọc, khỏi phải gọi lại API để refresh
  final DateTime updatedAt;
  final String? subjectApiUrl;

  GithubNotification({
    required this.id,
    required this.repoFullName,
    required this.subjectTitle,
    required this.subjectType,
    required this.reason,
    required this.unread,
    required this.updatedAt,
    this.subjectApiUrl,
  });

  factory GithubNotification.fromJson(Map<String, dynamic> json) {
    final subject = json['subject'] ?? {};
    final repo = json['repository'] ?? {};
    return GithubNotification(
      id: json['id'] ?? '',
      repoFullName: repo['full_name'] ?? '',
      subjectTitle: subject['title'] ?? '',
      subjectType: subject['type'] ?? '',
      reason: json['reason'] ?? '',
      unread: json['unread'] ?? false,
      updatedAt: DateTime.parse(json['updated_at']),
      subjectApiUrl: subject['url'],
    );
  }

  /// GitHub không trả sẵn html_url cho subject của notification, chỉ có url API
  /// (api.github.com/repos/...). Tự chuyển sang url trang web (github.com/...)
  /// để mở bằng trình duyệt. Lưu ý PR và Commit có đường dẫn web khác số ít/nhiều
  /// so với url API (pulls -> pull, commits -> commit).
  String get webUrl {
    final apiUrl = subjectApiUrl;
    if (apiUrl == null || apiUrl.isEmpty) {
      return 'https://github.com/$repoFullName';
    }
    final base = apiUrl.replaceFirst('https://api.github.com/repos/', 'https://github.com/');
    switch (subjectType) {
      case 'PullRequest':
        return base.replaceFirst('/pulls/', '/pull/');
      case 'Commit':
        return base.replaceFirst('/commits/', '/commit/');
      case 'Release':
        return 'https://github.com/$repoFullName/releases';
      case 'Discussion':
        return 'https://github.com/$repoFullName/discussions';
      default:
        return base;
    }
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
  final int id;
  final String name;
  final String status; // queued, in_progress, completed
  final String? conclusion; // success, failure, cancelled, ...
  final String branch;
  final String commitMessage;
  final DateTime createdAt;
  final String htmlUrl;

  WorkflowRun({
    required this.id,
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
      id: json['id'],
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

class WorkflowStep {
  final String name;
  final int number;
  final String status;
  final String? conclusion;

  WorkflowStep({required this.name, required this.number, required this.status, this.conclusion});

  factory WorkflowStep.fromJson(Map<String, dynamic> json) => WorkflowStep(
        name: json['name'] ?? '',
        number: json['number'] ?? 0,
        status: json['status'] ?? '',
        conclusion: json['conclusion'],
      );
}

class WorkflowJob {
  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final List<WorkflowStep> steps;

  WorkflowJob({
    required this.id,
    required this.name,
    required this.status,
    required this.steps,
    this.conclusion,
  });

  factory WorkflowJob.fromJson(Map<String, dynamic> json) {
    final List stepsJson = json['steps'] ?? [];
    return WorkflowJob(
      id: json['id'],
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      conclusion: json['conclusion'],
      steps: stepsJson.map((e) => WorkflowStep.fromJson(e)).toList(),
    );
  }
}

class Artifact {
  final int id;
  final String name;
  final int sizeInBytes;
  final String archiveDownloadUrl;
  final bool expired;

  Artifact({
    required this.id,
    required this.name,
    required this.sizeInBytes,
    required this.archiveDownloadUrl,
    required this.expired,
  });

  factory Artifact.fromJson(Map<String, dynamic> json) => Artifact(
        id: json['id'],
        name: json['name'] ?? '',
        sizeInBytes: json['size_in_bytes'] ?? 0,
        archiveDownloadUrl: json['archive_download_url'] ?? '',
        expired: json['expired'] ?? false,
      );
}

class GithubService {
  final String? token;
  GithubService({this.token});

  Map<String, String> get _headers => {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      };

  /// Tự động thử lại tối đa [maxAttempts] lần nếu gặp lỗi mạng chập chờn
  /// (không thử lại nếu là lỗi 401 hay lỗi khác không liên quan tới mạng).
  /// Thời gian chờ giữa các lần thử tăng dần (2s, 4s, 6s...) để có đủ thời gian
  /// cho mạng phục hồi nếu bị hệ điều hành tạm cắt mạng nền lúc app chuyển xuống nền.
  Future<T> _withRetry<T>(Future<T> Function() action, {int maxAttempts = 5}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (e) {
        final isNetworkGlitch = e.toString().contains('Connection closed') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection reset') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('connection abort') ||
            e.toString().contains('Network is unreachable');
        if (e is GithubUnauthorizedException || !isNetworkGlitch || attempt == maxAttempts) {
          LogService.instance.error('Gọi API GitHub thất bại (lần $attempt/$maxAttempts): $e');
          rethrow;
        }
        final delaySeconds = attempt * 2 > 15 ? 15 : attempt * 2;
        LogService.instance.warn('Lỗi mạng chập chờn, thử lại lần ${attempt + 1}/$maxAttempts sau ${delaySeconds}s: $e');
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
    throw Exception('Thất bại sau $maxAttempts lần thử');
  }

  void _checkStatus(http.Response response, String contextMessage) {
    if (response.statusCode == 401) {
      LogService.instance.error('GitHub API 401 Unauthorized: $contextMessage');
      throw GithubUnauthorizedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      LogService.instance.warn('GitHub API lỗi ${response.statusCode}: $contextMessage');
      throw Exception('$contextMessage (mã lỗi ${response.statusCode})');
    }
  }

  /// Liệt kê TẤT CẢ repo mà tài khoản đang đăng nhập có quyền truy cập
  /// (sở hữu, được thêm làm collaborator, hoặc thuộc tổ chức), kèm quyền hạn cụ thể.
  /// Tự động lấy hết các trang (phân trang) qua header 'Link' của GitHub.
  Future<List<GithubRepo>> listUserRepos() async {
    return _withRetry(() async {
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
    });
  }

  /// Liệt kê file/thư mục trong repo tại 1 path cụ thể.
  /// Repo public không cần token, repo private cần token có scope 'repo'.
  Future<List<GithubFile>> listContents(String owner, String repo, {String path = '', String? ref}) async {
    return _withRetry(() async {
      final query = ref != null ? <String, String>{'ref': ref} : null;
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path', query);
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được nội dung repo. Repo có thể là private, không tồn tại, hoặc token không đủ quyền.');

      final List data = jsonDecode(response.body);
      return data.map((e) => GithubFile.fromJson(e)).toList();
    });
  }

  /// Lấy thông tin (bao gồm download_url) của đúng 1 file, dùng khi chỉ có path
  /// (ví dụ từ kết quả tìm kiếm toàn repo, chưa có sẵn download_url).
  Future<GithubFile> getFileMeta(String owner, String repo, String path, {String? ref}) async {
    return _withRetry(() async {
      final query = ref != null ? <String, String>{'ref': ref} : null;
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path', query);
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được thông tin file');
      return GithubFile.fromJson(jsonDecode(response.body));
    });
  }

  /// Lấy default branch của repo (cần cho tìm kiếm toàn repo qua Git Trees API).
  Future<String> getDefaultBranch(String owner, String repo) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo');
    final response = await http.get(url, headers: _headers);
    _checkStatus(response, 'Không lấy được thông tin repo');
    final data = jsonDecode(response.body);
    return data['default_branch'] ?? 'main';
  }

  /// Lấy danh sách tên các branch của repo.
  Future<List<String>> listBranches(String owner, String repo) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/branches', {'per_page': '100'});
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được danh sách branch');
      final List data = jsonDecode(response.body);
      return data.map((e) => e['name'] as String).toList();
    });
  }

  /// Tìm kiếm file theo tên/đường dẫn trong TOÀN BỘ repo (mọi thư mục con),
  /// dùng Git Trees API (1 request lấy hết cây thư mục, nhanh hơn nhiều so với
  /// duyệt đệ quy từng thư mục). [ref] mặc định là default branch nếu không truyền.
  Future<List<GithubFile>> searchFilesInRepo(String owner, String repo, String query, {String? ref}) async {
    return _withRetry(() async {
      final branch = ref ?? await getDefaultBranch(owner, repo);
      // Dùng pathSegments thay vì nối chuỗi trực tiếp: branch chứa dấu "/" (rất
      // phổ biến, vd "feature/abc", "dependabot/npm_and_yarn/x") cần được mã hoá
      // thành 1 segment duy nhất (%2F) thì API git/trees mới hiểu đúng - khác với
      // API contents/... nhận ref qua query string nên không gặp vấn đề này.
      final url = Uri(
        scheme: 'https',
        host: 'api.github.com',
        pathSegments: ['repos', owner, repo, 'git', 'trees', branch],
        queryParameters: {'recursive': '1'},
      );
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không tìm kiếm được trong repo');

      final data = jsonDecode(response.body);
      final List tree = data['tree'] ?? [];
      final lowerQuery = query.toLowerCase();

      return tree
          .where((e) => e['type'] == 'blob' && (e['path'] as String).toLowerCase().contains(lowerQuery))
          .map((e) => GithubFile.fromTreeEntry(e))
          .toList();
    });
  }

  Future<List<int>> downloadFile(String downloadUrl) async {
    return _withRetry(() async {
      final response = await http.get(Uri.parse(downloadUrl), headers: _headers);
      _checkStatus(response, 'Tải file thất bại');
      return response.bodyBytes;
    });
  }

  /// Duyệt đệ quy toàn bộ file bên trong 1 thư mục (bao gồm thư mục con).
  /// Public để UI có thể gọi trước nhằm đếm số lượng file (cảnh báo nếu quá nhiều)
  /// trước khi thực sự tải xuống.
  Future<List<GithubFile>> listAllFilesRecursive(String owner, String repo, String path, {String? ref}) async {
    final entries = await listContents(owner, repo, path: path, ref: ref);
    final result = <GithubFile>[];
    for (final entry in entries) {
      if (entry.type == 'dir') {
        result.addAll(await listAllFilesRecursive(owner, repo, entry.path, ref: ref));
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
      if (folderPath.isNotEmpty) {
        // So khớp CHÍNH XÁC hoặc có "/" ngay sau, không dùng startsWith() suông -
        // trước đây "src".startsWith kiểu này sẽ khớp nhầm cả "src2/file.dart",
        // cắt còn lại "2/file.dart" (thiếu ký tự) nếu 2 thư mục trùng tiền tố tên.
        if (relativePath == folderPath) {
          relativePath = relativePath.substring(folderPath.length);
        } else if (relativePath.startsWith('$folderPath/')) {
          relativePath = relativePath.substring(folderPath.length + 1);
        }
      }

      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      onProgress?.call(i + 1, files.length);
    }

    final zipData = ZipEncoder().encode(archive);
    return zipData ?? [];
  }

  /// Lấy danh sách các lần chạy GitHub Actions gần nhất (build/CI).
  Future<List<WorkflowRun>> listWorkflowRuns(String owner, String repo) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/actions/runs', {'per_page': '30'});
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được trạng thái Actions');
      final data = jsonDecode(response.body);
      final List runs = data['workflow_runs'] ?? [];
      return runs.map((e) => WorkflowRun.fromJson(e)).toList();
    });
  }

  /// Lấy lịch sử commit gần nhất của repo.
  Future<List<GithubCommit>> listCommits(String owner, String repo) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/commits', {'per_page': '30'});
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được lịch sử commit');
      final List data = jsonDecode(response.body);
      return data.map((e) => GithubCommit.fromJson(e)).toList();
    });
  }

  /// Lấy ngày sửa đổi (commit) gần nhất của 1 file cụ thể.
  /// Lưu ý: mỗi lần gọi tốn 1 request API, nên chỉ dùng khi cần (vd: sort theo ngày).
  Future<DateTime?> getLastCommitDate(String owner, String repo, String path) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/commits', {'path': path, 'per_page': '1'});
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được ngày sửa đổi');
      final List data = jsonDecode(response.body);
      if (data.isEmpty) return null;
      final dateStr = data[0]['commit']?['author']?['date'];
      return dateStr != null ? DateTime.parse(dateStr) : null;
    });
  }

  /// Lấy danh sách job (và các bước/step bên trong) của 1 lần chạy Actions.
  Future<List<WorkflowJob>> listJobsForRun(String owner, String repo, int runId) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/actions/runs/$runId/jobs');
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được danh sách job');
      final data = jsonDecode(response.body);
      final List jobs = data['jobs'] ?? [];
      return jobs.map((e) => WorkflowJob.fromJson(e)).toList();
    });
  }

  /// Lấy toàn bộ log dạng text của 1 job.
  Future<String> getJobLogs(String owner, String repo, int jobId) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/actions/jobs/$jobId/logs');
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được log');
      return response.body;
    });
  }

  /// Lấy danh sách artifact (file build ra, ví dụ APK) của 1 lần chạy Actions.
  Future<List<Artifact>> listArtifacts(String owner, String repo, int runId) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/repos/$owner/$repo/actions/runs/$runId/artifacts');
      final response = await http.get(url, headers: _headers);
      _checkStatus(response, 'Không lấy được artifact');
      final data = jsonDecode(response.body);
      final List artifacts = data['artifacts'] ?? [];
      return artifacts.map((e) => Artifact.fromJson(e)).toList();
    });
  }

  /// Tải nội dung artifact (GitHub luôn đóng gói dạng .zip, kể cả khi bên trong chỉ có 1 file).
  /// Tải dạng stream để có thể báo tiến độ (%) qua [onProgress] thay vì chờ không rõ tiến trình.
  Future<List<int>> downloadArtifactZip(
    String archiveDownloadUrl, {
    void Function(int received, int? total)? onProgress,
  }) async {
    // File artifact có thể khá lớn (vài chục MB) và hay bị tải đúng lúc app chuyển
    // xuống nền - cho thử lại nhiều lần hơn + chờ lâu hơn giữa các lần thử so với
    // các API call nhỏ khác, để có đủ thời gian cho mạng phục hồi.
    return _withRetry(() async {
      // Dùng CHUNG 1 client cho cả request gốc lẫn request redirect (nếu có), rồi
      // đóng lại trong finally - trước đây mỗi lần gọi http.Client() tạo 1 client
      // mới nhưng không bao giờ .close(), rò rỉ connection/socket, nhất là khi
      // hàm này tự thử lại tới 8 lần cho file lớn.
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(archiveDownloadUrl));
        request.headers.addAll(_headers);
        request.followRedirects = false;

        var streamedResponse = await client.send(request);

        // GitHub trả về redirect (302) tới kho lưu trữ Azure Blob Storage - URL đó đã
        // có chữ ký sẵn trong query string, nên phải gọi lại KHÔNG kèm header
        // Authorization (gửi kèm sẽ bị Azure từ chối, trả về trang lỗi thay vì file zip).
        if (streamedResponse.statusCode == 301 || streamedResponse.statusCode == 302 || streamedResponse.statusCode == 303) {
          final location = streamedResponse.headers['location'];
          if (location == null) {
            throw Exception('Không tìm thấy địa chỉ chuyển hướng khi tải artifact');
          }
          final redirectRequest = http.Request('GET', Uri.parse(location));
          streamedResponse = await client.send(redirectRequest);
        }

        if (streamedResponse.statusCode == 401) throw GithubUnauthorizedException();
        if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
          throw Exception('Tải artifact thất bại (mã lỗi ${streamedResponse.statusCode})');
        }

        final total = streamedResponse.contentLength;
        final bytes = <int>[];
        await for (final chunk in streamedResponse.stream) {
          bytes.addAll(chunk);
          onProgress?.call(bytes.length, total);
        }

        // Nếu server có báo trước tổng dung lượng, kiểm tra tải đủ chưa - tránh
        // lưu nhầm file zip bị cắt cụt giữa chừng (gây lỗi khi giải nén).
        if (total != null && bytes.length != total) {
          throw Exception('Connection closed while receiving data (tải thiếu $total - ${bytes.length} bytes)');
        }

        return bytes;
      } finally {
        client.close();
      }
    }, maxAttempts: 8);
  }

  /// Cập nhật nội dung 1 file và commit thẳng lên GitHub.
  /// Cần [sha] hiện tại của file (lấy từ GithubFile.sha) để tránh ghi đè nhầm nếu file
  /// đã bị người khác thay đổi trong lúc bạn đang sửa.
  Future<void> updateFile(
    String owner,
    String repo,
    String path,
    String newContent,
    String sha, {
    String? commitMessage,
    String? branch,
  }) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path');
    final response = await http.put(
      url,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': commitMessage ?? 'Update $path via GitHub Repo Downloader',
        'content': base64Encode(utf8.encode(newContent)),
        'sha': sha,
        if (branch != null) 'branch': branch,
      }),
    );
    if (response.statusCode == 409) {
      throw Exception('File đã bị thay đổi ở nơi khác (conflict). Hãy mở lại file để lấy bản mới nhất rồi sửa lại.');
    }
    _checkStatus(response, 'Lưu file thất bại');
  }

  /// Tải 1 file MỚI (chưa tồn tại trong repo) lên, dùng cho tính năng "tải file từ máy lên repo".
  /// Khác với updateFile: không cần sha vì đây là tạo file mới, không phải sửa file có sẵn.
  Future<void> uploadNewFile(
    String owner,
    String repo,
    String path,
    List<int> bytes, {
    String? commitMessage,
    String? branch,
  }) async {
    final url = Uri.https('api.github.com', '/repos/$owner/$repo/contents/$path');
    final response = await http.put(
      url,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': commitMessage ?? 'Add $path via GitHub Repo Downloader',
        'content': base64Encode(bytes),
        if (branch != null) 'branch': branch,
      }),
    );
    if (response.statusCode == 422) {
      throw Exception('Đã tồn tại file tại đường dẫn này. Đổi tên khác hoặc dùng tính năng sửa file để ghi đè.');
    }
    _checkStatus(response, 'Tải file lên thất bại');
  }

  /// Lấy danh sách thông báo. [all]=false chỉ trả về thông báo CHƯA ĐỌC (mặc định
  /// của GitHub), [all]=true trả về cả thông báo đã đọc gần đây.
  /// Cần token có scope 'notifications' - nếu token cũ chưa có scope này, GitHub
  /// trả 404 dù endpoint tồn tại, nên coi 404 ở đây là lỗi thiếu quyền chứ không
  /// phải "không tìm thấy" thông thường.
  Future<List<GithubNotification>> listNotifications({bool all = false}) async {
    return _withRetry(() async {
      final url = Uri.https('api.github.com', '/notifications', {'all': all.toString(), 'per_page': '50'});
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 404) {
        throw Exception('Không lấy được thông báo (404). Tài khoản có thể cần đăng nhập lại để cấp thêm quyền đọc thông báo.');
      }
      _checkStatus(response, 'Không lấy được thông báo');
      final List data = jsonDecode(response.body);
      return data.map((e) => GithubNotification.fromJson(e)).toList();
    });
  }

  /// Đánh dấu 1 thông báo là đã đọc.
  Future<void> markNotificationRead(String threadId) async {
    final url = Uri.https('api.github.com', '/notifications/threads/$threadId');
    final response = await http.patch(url, headers: _headers);
    _checkStatus(response, 'Không đánh dấu đã đọc được');
  }

  /// Đánh dấu TOÀN BỘ thông báo là đã đọc.
  Future<void> markAllNotificationsRead() async {
    final url = Uri.https('api.github.com', '/notifications');
    final response = await http.put(url, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode({}));
    _checkStatus(response, 'Không đánh dấu tất cả đã đọc được');
  }
}
