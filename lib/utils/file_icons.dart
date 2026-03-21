/// Mapeo extensión → emoji, idéntico al frontend web (fileIcons.ts).
const Map<String, String> _fileIcons = {
  // Documents
  'pdf': '📄', 'doc': '📝', 'docx': '📝', 'txt': '📝',
  // Images
  'jpg': '🖼️', 'jpeg': '🖼️', 'png': '🖼️', 'gif': '🖼️', 'svg': '🖼️', 'webp': '🖼️',
  // Video
  'mp4': '🎬', 'avi': '🎬', 'mkv': '🎬', 'mov': '🎬',
  // Audio
  'mp3': '🎵', 'wav': '🎵', 'flac': '🎵', 'ogg': '🎵',
  // Archives
  'zip': '📦', 'rar': '📦', '7z': '📦', 'tar': '📦', 'gz': '📦',
  // Code
  'js': '⚙️', 'ts': '⚙️', 'py': '⚙️', 'java': '⚙️', 'cpp': '⚙️',
  // Web
  'html': '🌐', 'css': '🌐', 'json': '🌐',
  // Spreadsheets & Presentations
  'xlsx': '📊', 'xls': '📊', 'csv': '📊',
  'pptx': '📊', 'ppt': '📊',
};

const String _defaultIcon = '📁';

/// Devuelve un emoji que representa el tipo de archivo según su extensión.
String getFileIcon(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == filename.length - 1) return _defaultIcon;
  final ext = filename.substring(dotIndex + 1).toLowerCase();
  return _fileIcons[ext] ?? _defaultIcon;
}
