// File Name: pnl_provider.dart
// File Path: lib/features/pnl_history/presentation/providers/pnl_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/pnl_model.dart';
import '../../data/pnl_repository.dart';

/// Provider này sẽ tự động lắng nghe những thay đổi từ Firebase Database
final pnlHistoryStreamProvider = StreamProvider.autoDispose<List<RealizedPnl>>((ref) {
  final repository = ref.watch(pnlRepositoryProvider);
  return repository.watchRealizedPnls();
});