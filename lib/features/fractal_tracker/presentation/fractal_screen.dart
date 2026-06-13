// File Name: fractal_screen.dart
// File Path: lib/features/fractal_tracker/presentation/fractal_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers/fractal_provider.dart';

class FractalScreen extends ConsumerWidget {
  const FractalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fractalAsync = ref.watch(fractalDataProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text('BMAG Tracker (BTC)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(fractalDataProvider),
          )
        ],
      ),
      body: fractalAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: textColor)),
        error: (err, stack) => Center(child: Text('Lỗi tải dữ liệu', style: TextStyle(color: textColor))),
        data: (data) {
          if (data.isEmpty) return const Center(child: Text('Không có dữ liệu'));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(fractalDataProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  'MA TRẬN ĐỒNG PHA (CONFLUENCE)',
                  style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ...data.map((fData) => _buildFractalRow(fData, isDark)),
                const SizedBox(height: 32),
                _buildLegend(isDark),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFractalRow(dynamic data, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // Tính toán thời lượng của 1 ô (Quarter Duration) và Tiến trình của cả khung
    Duration? quarterDuration;
    double progress = 0.0;

    if (data.quarters.length == 4 && data.quarters[0].startTime != null && data.quarters[1].startTime != null) {
      final startTime = data.quarters[0].startTime!;
      quarterDuration = data.quarters[1].startTime!.difference(startTime);

      // Khung thời gian kết thúc = Bắt đầu của Q4 + Thời lượng 1 ô
      final endTime = data.quarters[3].startTime!.add(quarterDuration);

      final totalMs = endTime.difference(startTime).inMilliseconds;
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;

      if (totalMs > 0) {
        progress = (elapsedMs / totalMs).clamp(0.0, 1.0); // Giới hạn tiến trình từ 0% đến 100%
      }
    }

    // Tìm Cực đại (Max) và Cực tiểu (Min) của toàn bộ khung thời gian
    double? maxHigh;
    double? minLow;
    for (dynamic q in data.quarters) {
      if (q.high != null) {
        if (maxHigh == null || q.high > maxHigh) maxHigh = q.high;
      }
      if (q.low != null) {
        if (minLow == null || q.low < minLow) minLow = q.low;
      }
    }

    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Khung ${data.timeframeLabel}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: isDark ? Colors.white : Colors.black),
              ),
              Text(
                '\$${currencyFormat.format(data.currentPrice)}',
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
              )
            ],
          ),
          const SizedBox(height: 6),
          // THÊM DÒNG: Hiển thị giá Đỉnh và Đáy của khung
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🔥 Đỉnh: ${maxHigh != null ? currencyFormat.format(maxHigh) : '--'}',
                style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(
                '💧 Đáy: ${minLow != null ? currencyFormat.format(minLow) : '--'}',
                style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600),
              )
            ],
          ),
          const SizedBox(height: 12),

          // Row chứa 4 ô thời gian
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.quarters.map<Widget>((q) => Expanded(
              child: _buildQuarterBlock(q, quarterDuration, data.timeframeLabel, isDark),
            )).toList(),
          ),

          const SizedBox(height: 16),

          // Thanh Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tiến trình thời gian:', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  Text('${(progress * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade800, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white70 : Colors.blueAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Nhận thêm biến quarterDuration để tính toán thời gian kết thúc
  Widget _buildQuarterBlock(dynamic q, Duration? quarterDuration, String timeframe, bool isDark) {
    final isEmpty = q.isEmpty;
    final isGreen = q.isGreen;

    Color blockColor;
    if (isEmpty) {
      blockColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    } else {
      blockColor = isGreen ? Colors.green.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15);
    }

    Color textColor = isEmpty
        ? (isDark ? Colors.grey.shade600 : Colors.grey.shade400)
        : (isGreen ? Colors.green : Colors.redAccent);

    // Tính toán thời gian bắt đầu và kết thúc
    String timeStr = '';
    if (q.startTime != null && quarterDuration != null) {
      final endTime = q.startTime!.add(quarterDuration);

      if (timeframe == 'D1') {
        timeStr = '${DateFormat('HH:mm').format(q.startTime!)}\n-\n${DateFormat('HH:mm').format(endTime)}';
      } else {
        timeStr = '${DateFormat('dd/MM HH:mm').format(q.startTime!)}\n-\n${DateFormat('dd/MM HH:mm').format(endTime)}';
      }
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          height: 36,
          width: 52,
          decoration: BoxDecoration(
            color: blockColor,
            borderRadius: BorderRadius.circular(8),
            border: isEmpty ? null : Border.all(color: textColor.withOpacity(0.5), width: 1),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(q.name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
              if (q.hasAbsoluteHigh) const Positioned(top: 2, right: 2, child: Text('🔥', style: TextStyle(fontSize: 10))),
              if (q.hasAbsoluteLow) const Positioned(bottom: 2, right: 2, child: Text('💧', style: TextStyle(fontSize: 10))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // HIỂN THỊ THỜI GIAN BẮT ĐẦU & KẾT THÚC
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            fontWeight: FontWeight.w600,
            height: 1.3, // Khoảng cách giữa các dòng
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.visible,
        ),
      ],
    );
  }

  Widget _buildLegend(bool isDark) {
    Color tColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HƯỚNG DẪN XEM:', style: TextStyle(color: tColor, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('🔥: Cực đại (Đỉnh cao nhất của khung)', style: TextStyle(color: tColor, fontSize: 12)),
        const SizedBox(height: 4),
        Text('💧: Cực tiểu (Đáy thấp nhất của khung)', style: TextStyle(color: tColor, fontSize: 12)),
        const SizedBox(height: 4),
        Text('Màu nhạt: Khoảng thời gian chưa diễn ra.', style: TextStyle(color: tColor, fontSize: 12)),
      ],
    );
  }
}