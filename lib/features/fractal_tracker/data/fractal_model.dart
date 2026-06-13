// File Name: fractal_model.dart
// File Path: lib/features/fractal_tracker/data/fractal_model.dart

class QuarterData {
  final String name; // Q1, Q2, Q3, Q4
  DateTime? startTime; // THÊM MỚI: Mốc thời gian bắt đầu của phần này
  double? open;
  double? close;
  double? high;
  double? low;

  // Nến cũ nhất và mới nhất để lấy chuẩn Open/Close
  int? oldestTs;
  int? newestTs;

  bool hasAbsoluteHigh = false;
  bool hasAbsoluteLow = false;

  QuarterData(this.name);

  bool get isEmpty => open == null;
  bool get isGreen => (close ?? 0) >= (open ?? 0);
}

class FractalData {
  final String timeframeLabel; // 'D1', 'W1', 'M1', 'Y1'
  final List<QuarterData> quarters;
  final double currentPrice;

  FractalData({
    required this.timeframeLabel,
    required this.quarters,
    required this.currentPrice,
  });
}