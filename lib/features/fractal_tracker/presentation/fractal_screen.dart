// File Name: fractal_screen.dart
// File Path: lib/features/fractal_tracker/presentation/fractal_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers/fractal_provider.dart';
import '../data/fractal_model.dart';

// CHUYỂN ĐỔI THÀNH ConsumerStatefulWidget ĐỂ DÙNG TIMER
class FractalScreen extends ConsumerStatefulWidget {
  const FractalScreen({super.key});

  @override
  ConsumerState<FractalScreen> createState() => _FractalScreenState();
}

class _FractalScreenState extends ConsumerState<FractalScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // THÊM MỚI: Tự động invalidate (làm mới) provider mỗi 1 giây
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.invalidate(fractalDataProvider);
    });
  }

  @override
  void dispose() {
    // Nhớ tắt Timer khi thoát màn hình để giải phóng bộ nhớ
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text(
          'BMAG Tracker (BTC)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(fractalDataProvider),
          ),
        ],
      ),
      body: fractalAsync.when(
        // Rất quan trọng: Bỏ qua trạng thái Loading khi reload để app không bị chớp mỗi giây
        skipLoadingOnReload: true,
        loading: () =>
            Center(child: CircularProgressIndicator(color: textColor)),
        error: (err, stack) => Center(
          child: Text('Lỗi tải dữ liệu', style: TextStyle(color: textColor)),
        ),
        data: (data) {
          if (data.isEmpty)
            return const Center(child: Text('Không có dữ liệu'));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(fractalDataProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MA TRẬN ĐỒNG PHA (CONFLUENCE)',
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Thêm chấm xanh nhấp nháy biểu thị trạng thái LIVE
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
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
    final textColor = isDark ? Colors.white : Colors.black;

    Duration? quarterDuration;
    double progress = 0.0;

    if (data.quarters.length == 4 &&
        data.quarters[0].startTime != null &&
        data.quarters[1].startTime != null) {
      final startTime = data.quarters[0].startTime!;
      quarterDuration = data.quarters[1].startTime!.difference(startTime);
      final endTime = data.quarters[3].startTime!.add(quarterDuration);

      final totalMs = endTime.difference(startTime).inMilliseconds;
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;

      if (totalMs > 0) {
        progress = (elapsedMs / totalMs).clamp(0.0, 1.0);
      }
    }

    double? openPrice;
    double? maxHigh;
    double? minLow;
    for (dynamic q in data.quarters) {
      if (q.open != null && openPrice == null) openPrice = q.open;
      if (q.high != null) {
        if (maxHigh == null || q.high > maxHigh) maxHigh = q.high;
      }
      if (q.low != null) {
        if (minLow == null || q.low < minLow) minLow = q.low;
      }
    }

    if (maxHigh != null && data.currentPrice > maxHigh)
      maxHigh = data.currentPrice;
    if (minLow != null && data.currentPrice < minLow)
      minLow = data.currentPrice;

    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    Widget headerWidget;
    if (data.timeframeLabel == 'M1') {
      final month = ref.watch(selectedMonthProvider);
      headerWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.chevron_left, color: textColor, size: 26),
            onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                DateTime(month.year, month.month - 1),
          ),
          const SizedBox(width: 8),
          Text(
            'Tháng ${month.month}/${month.year}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.chevron_right, color: textColor, size: 26),
            onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                DateTime(month.year, month.month + 1),
          ),
        ],
      );
    } else if (data.timeframeLabel == 'Y1') {
      final year = ref.watch(selectedYearProvider);
      headerWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.chevron_left, color: textColor, size: 26),
            onPressed: () =>
                ref.read(selectedYearProvider.notifier).state = year - 1,
          ),
          const SizedBox(width: 8),
          Text(
            'Năm $year',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: textColor,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.chevron_right, color: textColor, size: 26),
            onPressed: () =>
                ref.read(selectedYearProvider.notifier).state = year + 1,
          ),
        ],
      );
    } else {
      headerWidget = Text(
        'Khung ${data.timeframeLabel}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: textColor,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              headerWidget,
              Text(
                '\$${currencyFormat.format(data.currentPrice)}',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mở: ${openPrice != null ? currencyFormat.format(openPrice) : '--'}',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '🔥 ${maxHigh != null ? currencyFormat.format(maxHigh) : '--'}',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '💧 ${minLow != null ? currencyFormat.format(minLow) : '--'}',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.quarters
                .map<Widget>(
                  (q) => Expanded(
                    child: _buildQuarterBlock(
                      q,
                      quarterDuration,
                      data.timeframeLabel,
                      isDark,
                      minLow,
                      maxHigh,
                    ),
                  ),
                )
                .toList(),
          ),

          if (data.subCandles.isNotEmpty) ...[
            Divider(
              height: 24,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
            Text(
              data.timeframeLabel == 'M1'
                  ? 'Diễn biến từng ngày'
                  : 'Diễn biến từng tháng',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.subCandles.map<Widget>((sc) {
                  return Expanded(
                    child: _buildMiniCandle(
                      sc,
                      minLow ?? 0,
                      maxHigh ?? 0,
                      isDark,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tiến trình thời gian:',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white70 : Colors.blueAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCandle(
    SubCandle sc,
    double overallMin,
    double overallMax,
    bool isDark,
  ) {
    final range = overallMax - overallMin;
    if (range <= 0) return const SizedBox();

    const double chartHeight = 45.0;

    double getY(double price) {
      final clampedPrice = price.clamp(overallMin, overallMax);
      return chartHeight - ((clampedPrice - overallMin) / range) * chartHeight;
    }

    final topY = getY(sc.high);
    final bottomY = getY(sc.low);
    final openY = getY(sc.open);
    final closeY = getY(sc.close);

    final isGreen = sc.close >= sc.open;
    final color = isGreen ? Colors.green : Colors.redAccent;

    double bodyTop = openY < closeY ? openY : closeY;
    double bodyBottom = openY > closeY ? openY : closeY;
    double bodyHeight = bodyBottom - bodyTop;

    if (bodyHeight < 1.0) bodyHeight = 1.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: chartHeight,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: topY,
                height: bottomY - topY,
                width: 1.0,
                child: Container(
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                ),
              ),
              Positioned(
                top: bodyTop,
                height: bodyHeight,
                width: 4.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.0),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sc.label,
          style: TextStyle(
            fontSize: 7.5,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildVerticalCandle(
    double overallMin,
    double overallMax,
    dynamic q,
    bool isDark,
  ) {
    const double height = 60.0;

    if (q.isEmpty ||
        q.open == null ||
        q.close == null ||
        q.high == null ||
        q.low == null) {
      return const SizedBox(height: height);
    }

    final range = overallMax - overallMin;
    if (range <= 0) return const SizedBox(height: height);

    double getY(double price) {
      final clampedPrice = price.clamp(overallMin, overallMax);
      return height - ((clampedPrice - overallMin) / range) * height;
    }

    final topY = getY(q.high!);
    final bottomY = getY(q.low!);
    final openY = getY(q.open!);
    final closeY = getY(q.close!);

    final isGreen = q.close! >= q.open!;
    final color = isGreen ? Colors.green : Colors.redAccent;

    double bodyTop = openY < closeY ? openY : closeY;
    double bodyBottom = openY > closeY ? openY : closeY;
    double bodyHeight = bodyBottom - bodyTop;

    if (bodyHeight < 2.0) {
      bodyHeight = 2.0;
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: topY,
            height: bottomY - topY,
            width: 1.5,
            child: Container(
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ),
          Positioned(
            top: bodyTop,
            height: bodyHeight,
            width: 8,
            child: Container(
              decoration: BoxDecoration(
                color: color.withOpacity(0.95),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuarterBlock(
    dynamic q,
    Duration? quarterDuration,
    String timeframe,
    bool isDark,
    double? minLow,
    double? maxHigh,
  ) {
    final isEmpty = q.isEmpty;
    final isGreen = q.isGreen;

    Color blockColor;
    if (isEmpty) {
      blockColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    } else {
      blockColor = isGreen
          ? Colors.green.withOpacity(0.15)
          : Colors.redAccent.withOpacity(0.15);
    }

    Color textColor = isEmpty
        ? (isDark ? Colors.grey.shade600 : Colors.grey.shade400)
        : (isGreen ? Colors.green : Colors.redAccent);

    String timeStr = '';
    if (q.startTime != null && quarterDuration != null) {
      final endTime = q.startTime!.add(quarterDuration);

      if (timeframe == 'D1') {
        timeStr =
            '${DateFormat('HH:mm').format(q.startTime!)}\n-\n${DateFormat('HH:mm').format(endTime)}';
      } else {
        timeStr =
            '${DateFormat('dd/MM HH:mm').format(q.startTime!)}\n-\n${DateFormat('dd/MM HH:mm').format(endTime)}';
      }
    }

    return Column(
      children: [
        if (minLow != null && maxHigh != null)
          _buildVerticalCandle(minLow, maxHigh, q, isDark),

        const SizedBox(height: 8),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          height: 36,
          width: 52,
          decoration: BoxDecoration(
            color: blockColor,
            borderRadius: BorderRadius.circular(8),
            border: isEmpty
                ? null
                : Border.all(color: textColor.withOpacity(0.5), width: 1),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                q.name,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (q.hasAbsoluteHigh)
                const Positioned(
                  top: 2,
                  right: 2,
                  child: Text('🔥', style: TextStyle(fontSize: 10)),
                ),
              if (q.hasAbsoluteLow)
                const Positioned(
                  bottom: 2,
                  right: 2,
                  child: Text('💧', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        Text(
          timeStr,
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            fontWeight: FontWeight.w600,
            height: 1.3,
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
        Text(
          'HƯỚNG DẪN XEM:',
          style: TextStyle(
            color: tColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '🔥: Cực đại (Đỉnh cao nhất của khung)',
          style: TextStyle(color: tColor, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          '💧: Cực tiểu (Đáy thấp nhất của khung)',
          style: TextStyle(color: tColor, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          'Biểu đồ nến dọc thể hiện độ dài ngắn (biên độ giá) của từng phân đoạn thời gian nhỏ.',
          style: TextStyle(color: tColor, fontSize: 12),
        ),
      ],
    );
  }
}
