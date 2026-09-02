import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/auth_service.dart';
import '../services/github_service.dart';
import '../services/downloads_service.dart';
import '../services/download_manager.dart';
import '../l10n/strings.dart';
import '../widgets/top_notification.dart';
import '../main.dart' show navigatorKey;
import 'login_screen.dart';
import 'actions_screen.dart';
import 'commits_screen.dart';
import 'repo_admin_screen.dart';
import 'code_search_screen.dart';
import '../widgets/file_editor_sheet.dart';

const int _bigFolderWarningThreshold = 200;
const int _bigDateSortWarningThreshold = 50;

enum SortOption { nameAsc, nameDesc, sizeAsc, sizeDesc, dateNewest, dateOldest }

String _sortLabel(SortOption option) {
  switch (option) {
    case SortOption.nameAsc:
      return t('browser.sort.name_asc');
    case SortOption.nameDesc:
      return t('browser.sort.name_desc');
    case SortOption.sizeAsc:
      return t('browser.sort.size_asc');
    case SortOption.sizeDesc:
      return t('browser.sort.size_desc');
    case SortOption.dateNewest:
      return t('browser.sort.date_newest');
    case SortOption.dateOldest:
      return t('browser.sort.date_oldest');
  }
}

String _formatSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class BrowserScreen extends StatefulWidget {
  final String? initialOwner;
  final String? initialRepo;

  const BrowserScreen({super.key, this.initialOwner, this.initialRepo});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _authService = AuthService();
  late final _ownerController = TextEditingController(text: widget.initialOwner ?? '');
  late final _repoController = TextEditingController(text: widget.initialRepo ?? '');
  final _searchController = TextEditingController();

  GithubService? _githubService;
  List<GithubFile> _files = [];
  String _currentPath = '';
  bool _loading = false;
  // "Đã mở repo thành công" - TÁCH RIÊNG khỏi _files.isNotEmpty. Trước đây dùng
  // chung _files.isNotEmpty để quyết định hiện nút Actions/Commits/Search/Upload,
  // khiến repo trống (0 file, vd repo mới tạo) bị coi như "chưa mở gì cả" và ẩn
  // mất cả nút Upload - vốn lẽ ra là cách để thêm file đầu tiên vào repo đó.
  bool _repoOpened = false;
  String? _username;

  String? _currentBranch; // null = đang dùng default branch của repo
  List<String> _branches = [];
  bool _branchesLoading = false;

  bool _searching = false;
  List<GithubFile> _searchResults = [];
  bool _searchLoading = false;

  SortOption _sortOption = SortOption.nameAsc;
  final Map<String, DateTime> _fileDates = {};
  bool _loadingDates = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final token = await _authService.getToken();
    final username = await _authService.getUsername();
    setState(() {
      _githubService = GithubService(token: token);
      _username = username;
    });
    if (widget.initialOwner != null && widget.initialRepo != null) {
      await _loadRepo();
    }
  }

  /// Bắt lỗi chung: nếu token hết hạn/bị thu hồi thì tự đăng xuất về màn hình login.
  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on GithubUnauthorizedException {
      await _authService.logout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('login.session_expired'))));
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
      return null;
    } catch (e) {
      _showError(e.toString());
      return null;
    }
  }

  /// Tải lại nội dung THƯ MỤC GỐC của repo hiện tại, theo _currentBranch đang có.
  /// Không đụng tới _currentBranch - dùng khi mở repo mới (branch đã set trước
  /// khi gọi) hoặc khi đổi branch qua _openBranchSwitcher.
  Future<void> _loadRootContents() async {
    setState(() {
      _loading = true;
      _currentPath = '';
      _fileDates.clear();
    });
    final files = await _guard(() => _githubService!.listContents(
          _ownerController.text.trim(),
          _repoController.text.trim(),
          ref: _currentBranch,
        ));
    // files != null nghĩa là gọi API thành công (repo tồn tại, có quyền truy cập)
    // dù danh sách file trả về có thể rỗng (repo trống) - đó vẫn tính là "đã mở".
    setState(() {
      if (files != null) _files = files;
      _repoOpened = files != null;
    });
    setState(() => _loading = false);
  }

  Future<void> _loadRepo() async {
    if (_ownerController.text.isEmpty || _repoController.text.isEmpty) return;
    setState(() {
      _currentBranch = null; // mở repo mới (khác trước đó) - quay về default branch
      _branches = [];
    });
    await _loadRootContents();
    if (!mounted) return;
    // Lấy tên default branch để HIỂN THỊ cho người dùng biết đang xem branch nào
    // (không chặn UI nếu lỗi - repo vẫn duyệt được bình thường, chỉ là không hiện tên).
    try {
      final branch = await _githubService!.getDefaultBranch(_ownerController.text.trim(), _repoController.text.trim());
      if (mounted) setState(() => _currentBranch = branch);
    } catch (_) {}
  }

  /// Hiện bottom sheet chọn branch, load lazy danh sách branch nếu chưa có.
  Future<void> _openBranchSwitcher() async {
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    if (owner.isEmpty || repo.isEmpty) return;

    if (_branches.isEmpty && !_branchesLoading) {
      setState(() => _branchesLoading = true);
      final list = await _guard(() => _githubService!.listBranches(owner, repo));
      if (mounted) {
        setState(() {
          _branches = list ?? [];
          _branchesLoading = false;
        });
      }
    }
    if (!mounted || _branches.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t('browser.branch_switcher_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _branches.length,
                itemBuilder: (context, index) {
                  final b = _branches[index];
                  return ListTile(
                    leading: Icon(b == _currentBranch ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                    title: Text(b),
                    onTap: () => Navigator.pop(ctx, b),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected != null && selected != _currentBranch) {
      setState(() => _currentBranch = selected);
      await _loadRootContents();
    }
  }

  Future<void> _openFolder(String path) async {
    setState(() {
      _loading = true;
      _fileDates.clear();
    });
    final files = await _guard(() => _githubService!.listContents(
          _ownerController.text.trim(),
          _repoController.text.trim(),
          path: path,
          ref: _currentBranch,
        ));
    if (files != null) {
      setState(() {
        _files = files;
        _currentPath = path;
      });
    }
    setState(() => _loading = false);
  }

  // Lùi lên đúng 1 cấp thư mục cha (dùng cho nút back AppBar/back cứng Android
  // - xem PopScope trong build()). "a/b/c" -> "a/b"; nếu đang ở thư mục gốc
  // của repo ("a" hoặc "") thì coi như không còn gì để lùi nữa.
  void _navigateUpOneLevel() {
    if (_currentPath.isEmpty) return;
    final segments = _currentPath.split('/')..removeLast();
    _openFolder(segments.join('/'));
  }

  void _downloadFile(GithubFile file) {
    if (file.downloadUrl == null) return;
    DownloadManager.instance.runDownload(
      label: file.name,
      navigatorKey: navigatorKey,
      fetch: (onProgress) => _githubService!.downloadFile(file.downloadUrl!),
      save: (bytes) => DownloadsService.saveBytes(file.name, bytes),
      onSuccess: (ctx, savedPath) => showTopNotification(ctx, t('common.saved_at', {'path': savedPath})),
      onError: (ctx, error) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error))),
    );
  }

  Future<void> _previewFile(GithubFile file) async {
    if (file.downloadUrl == null) return;
    final saved = await FileEditorSheet.show(
      context,
      owner: _ownerController.text.trim(),
      repo: _repoController.text.trim(),
      file: file,
      githubService: _githubService!,
      canEdit: true, // GitHub sẽ tự từ chối (403) nếu tài khoản không có quyền ghi
      branch: _currentBranch,
    );
    if (saved == true && mounted) {
      if (_currentPath.isEmpty) {
        await _loadRepo();
      } else {
        await _openFolder(_currentPath);
      }
    }
  }

  /// Logic dùng chung để tải 1 thư mục (hoặc cả repo, khi path rỗng) dạng .zip.
  /// Bước đếm file + xác nhận vẫn ở màn hình hiện tại (nhanh), nhưng bước tải
  /// + nén thực sự chạy nền qua DownloadManager để không chặn màn hình.
  Future<void> _downloadAsZip({required String path, required String displayName}) async {
    setState(() => _loading = true);
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final files = await _guard(() => _githubService!.listAllFilesRecursive(owner, repo, path, ref: _currentBranch));
    if (mounted) setState(() => _loading = false);
    if (files == null || !mounted) return;

    if (files.isEmpty) {
      _showError(t('browser.zip_no_files'));
      return;
    }

    final isBig = files.length > _bigFolderWarningThreshold;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('browser.zip_confirm_title', {'name': displayName})),
        content: Text(
          isBig
              ? t('browser.zip_confirm_big', {'count': files.length.toString()})
              : t('browser.zip_confirm_normal', {'count': files.length.toString()}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('browser.zip_download_button'))),
        ],
      ),
    );
    if (confirm != true) return;

    DownloadManager.instance.runDownload(
      label: '$displayName.zip',
      navigatorKey: navigatorKey,
      fetch: (onProgress) => _githubService!.zipFiles(
        files,
        path,
        onProgress: (done, total) => onProgress(total > 0 ? done / total : null),
      ),
      save: (bytes) => DownloadsService.saveBytes('$displayName.zip', bytes),
      onSuccess: (ctx, savedPath) => showTopNotification(ctx, t('common.saved_at', {'path': savedPath})),
      onError: (ctx, error) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(error))),
    );
  }

  /// Menu hành động khi nhấn giữ 1 dòng file/thư mục: tải xuống, xem/sửa,
  /// và (mới) xoá khỏi repo.
  Future<void> _showEntryActionsSheet(GithubFile entry, {required bool isDir}) async {
    final scheme = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 4),
            if (isDir)
              ListTile(
                leading: const Icon(Icons.archive_rounded),
                title: Text(t('browser.action_download_zip')),
                onTap: () => Navigator.pop(ctx, 'zip'),
              )
            else ...[
              if (isPreviewable(entry.name))
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: Text(t('browser.action_preview_edit')),
                  onTap: () => Navigator.pop(ctx, 'preview'),
                ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: Text(t('browser.action_download')),
                onTap: () => Navigator.pop(ctx, 'download'),
              ),
            ],
            ListTile(
              leading: Icon(Icons.delete_rounded, color: scheme.error),
              title: Text(
                isDir ? t('browser.action_delete_folder') : t('browser.action_delete_file'),
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'zip':
        await _downloadAsZip(path: entry.path, displayName: entry.name);
        break;
      case 'preview':
        await _previewFile(entry);
        break;
      case 'download':
        _downloadFile(entry);
        break;
      case 'delete':
        if (isDir) {
          await _confirmDeleteFolder(entry);
        } else {
          await _confirmDeleteFile(entry);
        }
        break;
    }
  }

  /// Xoá 1 file (sau khi xác nhận), tạo 1 commit xoá trên GitHub.
  Future<void> _confirmDeleteFile(GithubFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('browser.delete_file_confirm_title')),
        content: Text(t('browser.delete_file_confirm_body', {'name': file.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('browser.action_delete_file')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (file.sha == null) {
      _showError(t('browser.delete_missing_sha'));
      return;
    }

    setState(() => _loading = true);
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final ok = await _guard(() => _githubService!.deleteFile(owner, repo, file.path, file.sha!, branch: _currentBranch).then((_) => true));
    if (mounted) setState(() => _loading = false);
    if (ok == null || !mounted) return;

    showTopNotification(context, t('browser.delete_file_done', {'name': file.name}));
    await _openFolder(_currentPath);
  }

  /// Xoá TOÀN BỘ file bên trong 1 thư mục (sau khi xác nhận + cho biết trước
  /// số lượng file, vì mỗi file là 1 commit riêng - có thể mất một lúc nếu
  /// thư mục có nhiều file).
  Future<void> _confirmDeleteFolder(GithubFile folder) async {
    setState(() => _loading = true);
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final files = await _guard(() => _githubService!.listAllFilesRecursive(owner, repo, folder.path, ref: _currentBranch));
    if (mounted) setState(() => _loading = false);
    if (files == null || !mounted) return;
    if (files.isEmpty) {
      _showError(t('browser.zip_no_files'));
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('browser.delete_folder_confirm_title')),
        content: Text(t('browser.delete_folder_confirm_body', {'name': folder.name, 'count': files.length.toString()})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('browser.action_delete_folder')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    final ok = await _guard(() => _githubService!.deleteFolder(owner, repo, files, branch: _currentBranch).then((_) => true));
    if (mounted) setState(() => _loading = false);
    if (ok == null || !mounted) return;

    showTopNotification(context, t('browser.delete_folder_done', {'name': folder.name, 'count': files.length.toString()}));
    await _openFolder(_currentPath);
  }

  Future<void> _downloadWholeRepoAsZip() =>
      _downloadAsZip(path: '', displayName: _repoController.text.trim());

  /// Chọn 1 file từ máy, xác nhận tên/commit message, rồi tải lên thành file mới trong repo
  /// (tại thư mục đang duyệt hiện tại).
  Future<void> _handleUploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      _showError(t('browser.upload_read_error'));
      return;
    }

    final nameController = TextEditingController(text: picked.name);
    final messageController = TextEditingController(text: 'Add ${picked.name} via GitHub Repo Downloader');

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('browser.upload_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: t('browser.upload_filename_label'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: InputDecoration(labelText: t('editor.commit_message_label'), border: const OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('browser.upload_button'))),
        ],
      ),
    );
    if (confirmed != true) return;

    final targetPath = _currentPath.isEmpty ? nameController.text.trim() : '$_currentPath/${nameController.text.trim()}';

    setState(() => _loading = true);
    final success = await _guard(() => _githubService!.uploadNewFile(
          _ownerController.text.trim(),
          _repoController.text.trim(),
          targetPath,
          bytes,
          commitMessage: messageController.text.trim(),
          branch: _currentBranch,
        ).then((_) => true));
    if (mounted) setState(() => _loading = false);

    if (success == true && mounted) {
      showTopNotification(context, t('browser.upload_success'));
      if (_currentPath.isEmpty) {
        await _loadRepo();
      } else {
        await _openFolder(_currentPath);
      }
    }
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    final results = await _guard(() => _githubService!.searchFilesInRepo(
          _ownerController.text.trim(),
          _repoController.text.trim(),
          query.trim(),
          ref: _currentBranch,
        ));
    if (results != null) setState(() => _searchResults = results);
    setState(() => _searchLoading = false);
  }

  Future<void> _openSearchResult(GithubFile result, {required bool preview}) async {
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final meta = await _guard(() => _githubService!.getFileMeta(owner, repo, result.path, ref: _currentBranch));
    if (meta == null) return;
    if (preview) {
      await _previewFile(meta);
    } else {
      _downloadFile(meta);
    }
  }

  /// Chọn kiểu sắp xếp. Nếu chọn theo ngày mà chưa có dữ liệu ngày, sẽ tự tải trước.
  Future<void> _selectSort(SortOption option) async {
    setState(() => _sortOption = option);

    final needsDate = option == SortOption.dateNewest || option == SortOption.dateOldest;
    if (!needsDate) return;

    final filesNeedingDate = _files.where((f) => f.type == 'file' && !_fileDates.containsKey(f.path)).toList();
    if (filesNeedingDate.isEmpty) return;

    if (filesNeedingDate.length > _bigDateSortWarningThreshold) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t('browser.date_sort_warning_title')),
          content: Text(t('browser.date_sort_warning_body', {'count': filesNeedingDate.length.toString()})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('common.continue'))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _loadingDates = true);
    for (final file in filesNeedingDate) {
      final date = await _guard(() => _githubService!.getLastCommitDate(
            _ownerController.text.trim(),
            _repoController.text.trim(),
            file.path,
          ));
      if (date != null) _fileDates[file.path] = date;
    }
    if (mounted) setState(() => _loadingDates = false);
  }

  /// Luôn đưa thư mục lên trước, sau đó sắp xếp file theo tiêu chí đang chọn.
  List<GithubFile> get _sortedFiles {
    final dirs = _files.where((f) => f.type == 'dir').toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = _files.where((f) => f.type == 'file').toList();

    switch (_sortOption) {
      case SortOption.nameAsc:
        files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortOption.nameDesc:
        files.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case SortOption.sizeAsc:
        files.sort((a, b) => (a.size ?? 0).compareTo(b.size ?? 0));
        break;
      case SortOption.sizeDesc:
        files.sort((a, b) => (b.size ?? 0).compareTo(a.size ?? 0));
        break;
      case SortOption.dateNewest:
        files.sort((a, b) =>
            (_fileDates[b.path] ?? DateTime(0)).compareTo(_fileDates[a.path] ?? DateTime(0)));
        break;
      case SortOption.dateOldest:
        files.sort((a, b) =>
            (_fileDates[a.path] ?? DateTime(0)).compareTo(_fileDates[b.path] ?? DateTime(0)));
        break;
    }

    return [...dirs, ...files];
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repoIsOpen = _ownerController.text.isNotEmpty && _repoController.text.isNotEmpty && _repoOpened;

    // Đang ở trong 1 thư mục con (không phải gốc repo) -> nút back (AppBar lẫn
    // back cứng Android) chỉ nên lùi lên 1 cấp thư mục, không thoát hẳn ra khỏi
    // repo. Chỉ khi đang ở gốc mới cho phép pop thật (thoát BrowserScreen).
    final canPopScreen = _currentPath.isEmpty;

    return PopScope(
      canPop: canPopScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _navigateUpOneLevel();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_username != null ? t('browser.title_named', {'username': _username!}) : t('browser.title_generic')),
        actions: [
          if (repoIsOpen) ...[
            IconButton(
              icon: const Icon(Icons.play_circle_outline_rounded),
              tooltip: t('browser.actions_tooltip'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ActionsScreen(
                    owner: _ownerController.text.trim(),
                    repo: _repoController.text.trim(),
                    githubService: _githubService!,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: t('browser.commits_tooltip'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommitsScreen(
                    owner: _ownerController.text.trim(),
                    repo: _repoController.text.trim(),
                    githubService: _githubService!,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
              tooltip: t('browser.search_tooltip'),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchController.clear();
                  _searchResults = [];
                }
              }),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file_rounded),
              tooltip: t('browser.upload_tooltip'),
              onPressed: _handleUploadFile,
            ),
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_rounded),
              tooltip: t('browser.admin_tooltip'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RepoAdminScreen(
                    owner: _ownerController.text.trim(),
                    repo: _repoController.text.trim(),
                    githubService: _githubService!,
                  ),
                ),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.travel_explore_rounded),
            tooltip: t('browser.global_search_tooltip'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CodeSearchScreen(githubService: _githubService!)),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout),
        ],
      ),
      floatingActionButton: repoIsOpen && !_searching
          ? FloatingActionButton.extended(
              onPressed: _downloadWholeRepoAsZip,
              icon: const Icon(Icons.folder_zip_rounded),
              label: Text(t('browser.download_whole_repo')),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ownerController,
                    decoration: InputDecoration(
                      labelText: t('browser.owner_label'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _repoController,
                    decoration: InputDecoration(
                      labelText: t('browser.repo_label'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loadRepo, child: Text(t('browser.open_button'))),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: t('browser.search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: _runSearch,
              ),
            ),
          if (repoIsOpen && !_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: _branchesLoading
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                      : Icon(Icons.alt_route_rounded, size: 16, color: scheme.primary),
                  label: Text(_currentBranch ?? '…'),
                  onPressed: _openBranchSwitcher,
                ),
              ),
            ),
          if (_currentPath.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '📁 /$_currentPath',
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (!_loading && _files.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('browser.hint_long_press_zip'),
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  PopupMenuButton<SortOption>(
                    tooltip: t('browser.sort_tooltip'),
                    onSelected: _selectSort,
                    icon: Icon(Icons.sort_rounded, size: 20, color: scheme.primary),
                    itemBuilder: (ctx) => SortOption.values
                        .map((o) => PopupMenuItem(
                              value: o,
                              child: Row(
                                children: [
                                  if (_sortOption == o) Icon(Icons.check_rounded, size: 16, color: scheme.primary),
                                  if (_sortOption == o) const SizedBox(width: 6),
                                  Text(_sortLabel(o)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          if (_loading || _searchLoading || _loadingDates) const LinearProgressIndicator(),
          Expanded(
            child: _searching
                ? _buildSearchResults(scheme)
                : _files.isEmpty && !_loading
                    ? Center(
                        child: Text(
                          _repoOpened ? t('browser.repo_empty') : t('browser.empty_state'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.outline),
                        ),
                      )
                    : _buildFileList(scheme),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme scheme) {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.isEmpty ? t('browser.search_hint_empty') : t('browser.search_no_match'),
          style: TextStyle(color: scheme.outline),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        final canPreview = isPreviewable(result.name);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.insert_drive_file_rounded),
            title: Text(result.name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(result.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPreview)
                  IconButton(
                    icon: const Icon(Icons.visibility_rounded),
                    onPressed: () => _openSearchResult(result, preview: true),
                  ),
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () => _openSearchResult(result, preview: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileList(ColorScheme scheme) {
    final sorted = _sortedFiles;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final file = sorted[index];
        final isDir = file.type == 'dir';
        final canPreview = !isDir && isPreviewable(file.name);
        final dateStr = _fileDates.containsKey(file.path) ? _formatSizeOrDate(file) : null;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 0,
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: CircleAvatar(
              backgroundColor: isDir ? scheme.primaryContainer : scheme.secondaryContainer,
              child: Icon(
                isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                color: isDir ? scheme.onPrimaryContainer : scheme.onSecondaryContainer,
                size: 20,
              ),
            ),
            title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: !isDir
                ? Text(
                    dateStr ?? _formatSize(file.size),
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  )
                : null,
            trailing: isDir
                ? const Icon(Icons.chevron_right_rounded)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canPreview)
                        IconButton(icon: const Icon(Icons.visibility_rounded), onPressed: () => _previewFile(file)),
                      IconButton(icon: const Icon(Icons.download_rounded), onPressed: () => _downloadFile(file)),
                    ],
                  ),
            onTap: isDir ? () => _openFolder(file.path) : (canPreview ? () => _previewFile(file) : null),
            onLongPress: () => _showEntryActionsSheet(file, isDir: isDir),
          ),
        );
      },
    );
  }

  String _formatSizeOrDate(GithubFile file) {
    final date = _fileDates[file.path];
    if (date == null) return _formatSize(file.size);
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ${_formatSize(file.size)}';
  }
}
