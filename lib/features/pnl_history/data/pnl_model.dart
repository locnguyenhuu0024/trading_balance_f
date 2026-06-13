// File Name: pnl_model.dart
// File Path: lib/features/pnl_history/data/pnl_model.dart

class RealizedPnl {
  final String? id; // Thêm ID để phân biệt các dòng
  final double amount;
  final String note;
  final DateTime timestamp;

  RealizedPnl({
    this.id,
    required this.amount,
    required this.note,
    required this.timestamp,
  });

  // Chuyển Object thành Map (JSON) để đẩy lên Firebase
  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'note': note,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // THÊM MỚI: Chuyển Map (JSON) từ Firebase về lại Object Dart
  factory RealizedPnl.fromMap(Map<String, dynamic> map, String docId) {
    return RealizedPnl(
      id: docId,
      amount: map['amount']?.toDouble() ?? 0.0,
      note: map['note'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}