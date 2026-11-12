/// Mapeo extensión → emoji, idéntico al frontend web (fileIcons.ts).
const Map<String, String> _fileIcons = {
  // Documents & text
  'doc': '📝', 'docx': '📝', 'odt': '📝', 'rtf': '📝', 'txt': '📝', 'md': '📝', 'markdown': '📝', 'mdx': '📝', 'rst': '📝', 'log': '📝', 'tex': '📝',
  // PDF
  'pdf': '📄',
  // Images
  'jpg': '🖼️', 'jpeg': '🖼️', 'png': '🖼️', 'gif': '🖼️', 'svg': '🖼️', 'webp': '🖼️', 'bmp': '🖼️', 'ico': '🖼️', 'heic': '🖼️', 'heif': '🖼️', 'avif': '🖼️', 'tif': '🖼️', 'tiff': '🖼️',
  // Video
  'mp4': '🎬', 'avi': '🎬', 'mkv': '🎬', 'mov': '🎬', 'webm': '🎬', 'm4v': '🎬', '3gp': '🎬', 'wmv': '🎬',
  // Audio
  'mp3': '🎵', 'wav': '🎵', 'flac': '🎵', 'ogg': '🎵', 'm4a': '🎵', 'aac': '🎵', 'opus': '🎵', 'wma': '🎵',
  // Archives
  'zip': '📦', 'rar': '📦', '7z': '📦', 'tar': '📦', 'gz': '📦', 'bz2': '📦', 'xz': '📦', 'tgz': '📦',
  // Apps & installers
  'apk': '💿', 'aab': '💿', 'exe': '💿', 'msi': '💿', 'dmg': '💿', 'pkg': '💿', 'deb': '💿', 'rpm': '💿', 'appimage': '💿', 'iso': '💿',
  // Code
  'js': '⚙️', 'jsx': '⚙️', 'ts': '⚙️', 'tsx': '⚙️', 'py': '⚙️', 'java': '⚙️', 'kt': '⚙️', 'swift': '⚙️', 'dart': '⚙️', 'go': '⚙️', 'rs': '⚙️', 'c': '⚙️', 'h': '⚙️', 'cpp': '⚙️', 'cs': '⚙️', 'php': '⚙️', 'rb': '⚙️', 'sh': '⚙️', 'bat': '⚙️', 'ps1': '⚙️', 'sql': '⚙️',
  // Web & data
  'html': '🌐', 'htm': '🌐', 'css': '🌐', 'json': '🌐', 'xml': '🌐', 'yaml': '🌐', 'yml': '🌐', 'toml': '🌐', 'ini': '🌐', 'env': '🌐',
  // Spreadsheets & presentations
  'xlsx': '📊', 'xls': '📊', 'ods': '📊', 'csv': '📊', 'tsv': '📊', 'pptx': '📊', 'ppt': '📊', 'odp': '📊', 'key': '📊', 'numbers': '📊',
};

/// Archivo genérico (antes 📁, que parecía una carpeta).
const String _defaultIcon = '📃';

/// Devuelve un emoji que representa el tipo de archivo según su extensión.
String getFileIcon(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == filename.length - 1) return _defaultIcon;
  final ext = filename.substring(dotIndex + 1).toLowerCase();
  return _fileIcons[ext] ?? _defaultIcon;
}
