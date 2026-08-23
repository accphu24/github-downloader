import 'package:flutter/material.dart';
import '../l10n/strings.dart';

enum DiffLineType { unchanged, added, removed }

class DiffLine {
  final DiffLineType type;
  final String text;
  const DiffLine(this.type, this.text);
}

/// Giới hạn an toàn: bảng quy hoạch động của LCS có kích thước ~(số dòng)²,
/// file quá lớn có thể tốn hàng trăm MB RAM trên điện thoại. Vượt ngưỡng này
/// thì bỏ qua diff chi tiết, chỉ hiện thông báo file quá lớn.
const _maxDiffLines = 2000;

int _countLines(String text) => '\n'.allMatches(text).length + 1;

/// Tính diff theo dòng giữa 2 đoạn text bằng thuật toán LCS (Longest Common
/// Subsequence) cổ điển qua quy hoạch động - độ phức tạp O(n*m), đủ nhanh cho
/// file text thông thường. Trả null nếu 1 trong 2 bên vượt quá _maxDiffLines dòng.
List<DiffLine>? computeLineDiff(String oldText, String newText) {
  final oldLines = oldText.split('\n');
  final newLines = newText.split('\n');
  final n = oldLines.length;
  final m = newLines.length;
  if (n > _maxDiffLines || m > _maxDiffLines) return null;

  // dp[i][j] = độ dài LCS giữa oldLines[i..] và newLines[j..]
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (oldLines[i] == newLines[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  final result = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (oldLines[i] == newLines[j]) {
      result.add(DiffLine(DiffLineType.unchanged, oldLines[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      result.add(DiffLine(DiffLineType.removed, oldLines[i]));
      i++;
    } else {
      result.add(DiffLine(DiffLineType.added, newLines[j]));
      j++;
    }
  }
  while (i < n) {
    result.add(DiffLine(DiffLineType.removed, oldLines[i]));
    i++;
  }
  while (j < m) {
    result.add(DiffLine(DiffLineType.added, newLines[j]));
    j++;
  }
  return result;
}

Color? _bgFor(DiffLineType type) {
  if (type == DiffLineType.added) return Colors.green.withValues(alpha: 0.15);
  if (type == DiffLineType.removed) return Colors.red.withValues(alpha: 0.15);
  return null;
}

String _prefixFor(DiffLineType type) {
  if (type == DiffLineType.added) return '+ ';
  if (type == DiffLineType.removed) return '- ';
  return '  ';
}

Color _fgFor(DiffLineType type, ColorScheme scheme) {
  if (type == DiffLineType.added) return Colors.green.shade800;
  if (type == DiffLineType.removed) return Colors.red.shade800;
  return scheme.onSurface.withValues(alpha: 0.7);
}

/// Bottom sheet hiện diff (thay đổi) trước khi commit, kèm ô nhập commit
/// message. Trả về commit message qua Navigator nếu người dùng xác nhận
/// commit, null nếu huỷ.
class DiffPreviewSheet extends StatefulWidget {
  final String fileName;
  final String oldContent;
  final String newContent;
  final String initialCommitMessage;

  const DiffPreviewSheet({
    super.key,
    required this.fileName,
    required this.oldContent,
    required this.newContent,
    required this.initialCommitMessage,
  });

  static Future<String?> show(
    BuildContext context, {
    required String fileName,
    required String oldContent,
    required String newContent,
    required String initialCommitMessage,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DiffPreviewSheet(
        fileName: fileName,
        oldContent: oldContent,
        newContent: newContent,
        initialCommitMessage: initialCommitMessage,
      ),
    );
  }

  @override
  State<DiffPreviewSheet> createState() => _DiffPreviewSheetState();
}

class _DiffPreviewSheetState extends State<DiffPreviewSheet> {
  late final TextEditingController _messageController;
  List<DiffLine>? _diffLines;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: widget.initialCommitMessage);
    final oldCount = _countLines(widget.oldContent);
    final newCount = _countLines(widget.newContent);
    if (oldCount <= _maxDiffLines && newCount <= _maxDiffLines) {
      _diffLines = computeLineDiff(widget.oldContent, widget.newContent);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diffLines = _diffLines;
    final added = diffLines?.where((l) => l.type == DiffLineType.added).length ?? 0;
    final removed = diffLines?.where((l) => l.type == DiffLineType.removed).length ?? 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.fileName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          if (diffLines != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+$added  -$removed',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary),
                ),
              ),
            ),
          const Divider(height: 16),
          Expanded(
            child: diffLines == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(t('editor.diff_too_large'), textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
                    ),
                  )
                : diffLines.isEmpty
                    ? Center(child: Text(t('editor.diff_no_changes'), style: TextStyle(color: scheme.outline)))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: diffLines.length,
                        itemBuilder: (context, index) {
                          final line = diffLines[index];
                          return Container(
                            width: double.infinity,
                            color: _bgFor(line.type),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            child: Text(
                              '${_prefixFor(line.type)}${line.text}',
                              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: _fgFor(line.type, scheme)),
                            ),
                          );
                        },
                      ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _messageController,
                  decoration: InputDecoration(labelText: t('editor.commit_message_label'), border: const OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t('common.cancel')))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _messageController.text.trim()),
                        child: Text(t('editor.commit_button')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
