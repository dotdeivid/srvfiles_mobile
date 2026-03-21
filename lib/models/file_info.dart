class FileInfo {
  final String name;
  final int size;
  final String createdAt;
  final String downloadUrl;

  const FileInfo({
    required this.name,
    required this.size,
    required this.createdAt,
    required this.downloadUrl,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) => FileInfo(
        name: json['name'] as String,
        size: json['size'] as int,
        createdAt: json['createdAt'] as String,
        downloadUrl: json['downloadUrl'] as String,
      );
}
