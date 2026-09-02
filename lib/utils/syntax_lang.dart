/// Map đuôi file -> tên ngôn ngữ mà gói `highlight` (dùng bởi
/// `flutter_highlight`) nhận diện được, để tô màu cú pháp khi xem file trong
/// FileEditorSheet. Trả về null nếu không nhận diện được (sẽ fallback về
/// hiển thị text thường, không tô màu).
String? highlightLanguageForFile(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  const map = {
    'dart': 'dart',
    'js': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'py': 'python',
    'java': 'java',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'go': 'go',
    'rs': 'rust',
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'cc': 'cpp',
    'hpp': 'cpp',
    'cs': 'csharp',
    'php': 'php',
    'rb': 'ruby',
    'swift': 'swift',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'yml': 'yaml',
    'yaml': 'yaml',
    'json': 'json',
    'xml': 'xml',
    'html': 'xml',
    'htm': 'xml',
    'css': 'css',
    'scss': 'scss',
    'sql': 'sql',
    'dockerfile': 'dockerfile',
    'gradle': 'gradle',
    'kts.gradle': 'gradle',
    'toml': 'ini',
    'ini': 'ini',
    'properties': 'ini',
  };
  return map[ext];
}
