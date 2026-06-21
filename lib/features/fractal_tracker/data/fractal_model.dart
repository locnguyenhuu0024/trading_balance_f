// File Name: fractal_model.dart
// File Path: lib/features/fractal_tracker/data/fractal_model.dart

class QuarterData {
  final String name; // Q1, Q2, Q3, Q4
  DateTime? startTime;
  double? open;
  double? close;
  double? high;
  double? low;

  int? oldestTs;
  int? newestTs;

  bool hasAbsoluteHigh = false;
  bool hasAbsoluteLow = false;

  QuarterData(this.name);

  bool get isEmpty => open == null;
  bool get isGreen => (close ?? 0) >= (open ?? 0);
}

// THÊM MỚI: Cấu trúc Nến nhỏ (Dùng cho Nến Ngày trong Tháng, hoặc Nến Tháng trong Năm)
class SubCandle {
  final String label; // Ví dụ: "1", "2", "3" (Ngày) hoặc "1", "2", "12" (Tháng)
  final double open;
  final double high;
  final double low;
  final double close;

  SubCandle(this.label, this.open, this.high, this.low, this.close);

  bool get isGreen => close >= open;
}

class FractalData {
  final String timeframeLabel;
  final List<QuarterData> quarters;
  final double currentPrice;
  final List<SubCandle> subCandles; // THÊM MỚI: Danh sách các nến nhỏ

  FractalData({
    required this.timeframeLabel,
    required this.quarters,
    required this.currentPrice,
    this.subCandles = const [], // Mặc định là rỗng
  });
}
