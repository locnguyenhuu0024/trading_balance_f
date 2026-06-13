// File Name: pnl_repository.dart
// File Path: lib/features/pnl_history/data/pnl_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pnl_model.dart';

final pnlRepositoryProvider = Provider<PnlRepository>((ref) {
  return PnlRepository(FirebaseFirestore.instance);
});

class PnlRepository {
  final FirebaseFirestore _firestore;

  PnlRepository(this._firestore);

  /// Hàm ghi Lãi/Lỗ mới lên Firestore
  Future<void> addRealizedPnl(RealizedPnl pnl) async {
    try {
      await _firestore.collection('realized_pnl').add(pnl.toMap());
    } catch (e) {
      throw Exception('Không thể lưu lên mây: $e');
    }
  }

  /// THÊM MỚI: Luồng dữ liệu đọc trực tiếp Lịch sử từ Firestore (Cập nhật realtime)
  Stream<List<RealizedPnl>> watchRealizedPnls() {
    return _firestore
        .collection('realized_pnl')
        .orderBy('timestamp', descending: true) // Sắp xếp mới nhất lên đầu
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => RealizedPnl.fromMap(doc.data(), doc.id))
          .toList();
    });
  }
}