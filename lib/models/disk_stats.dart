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
        total: (json['total'] as num?)?.toInt() ?? 0,
        used: (json['used'] as num?)?.toInt() ?? 0,
        free: (json['free'] as num?)?.toInt() ?? 0,
      );

  double get usedPercent => total > 0 ? (used / total) * 100 : 0;
  bool get isWarning => usedPercent > 80;
  bool get isCritical => usedPercent > 95;
}
