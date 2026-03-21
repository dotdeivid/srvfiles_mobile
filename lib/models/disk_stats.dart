class DiskStats {
  final int total;
  final int used;
  final int free;

  const DiskStats({
    required this.total,
    required this.used,
    required this.free,
  });

  factory DiskStats.fromJson(Map<String, dynamic> json) => DiskStats(
        total: json['total'] as int,
        used: json['used'] as int,
        free: json['free'] as int,
      );

  double get usedPercent => total > 0 ? (used / total) * 100 : 0;
  bool get isWarning => usedPercent > 80;
  bool get isCritical => usedPercent > 95;
}
