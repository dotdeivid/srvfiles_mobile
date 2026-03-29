/// Classifies a file by its extension into a [FileCategory].
enum FileCategory { image, svg, video, audio, pdf, text, unknown }

class FileTypeHelper {
  FileTypeHelper._();

  static const _extensions = <FileCategory, List<String>>{
    FileCategory.image: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico'],
    FileCategory.svg:   ['svg'],
    FileCategory.video: ['mp4', 'mov', 'm4v', 'webm'],
    FileCategory.audio: ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac', 'opus'],
    FileCategory.pdf:   ['pdf'],
    FileCategory.text:  [
      'txt', 'md', 'json', 'xml', 'csv', 'yaml', 'yml',
      'html', 'htm', 'js', 'jsx', 'ts', 'tsx', 'dart',
      'py', 'go', 'rs', 'swift', 'kt', 'java',
      'c', 'cpp', 'h', 'css', 'sh', 'bash', 'zsh',
    ],
  };

  /// Returns the [FileCategory] for [fileName].
  static FileCategory categorize(String fileName) {
    final ext = _ext(fileName);
    for (final entry in _extensions.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }
    return FileCategory.unknown;
  }

  /// Returns true if the file can be previewed inline.
  static bool canPreview(String fileName) =>
      categorize(fileName) != FileCategory.unknown;

  static String _ext(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
