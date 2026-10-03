// File Name: fractal_screen.dart
// File Path: lib/features/fractal_tracker/presentation/fractal_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/formatting/adaptive_number_format.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/timezone/app_time_zone.dart';
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
    final selectedCoin = ref.watch(
      selectedCoinProvider,
    ); // THÊM MỚI: Lấy coin đang chọn
    final timeZoneId = ref.watch(appTimeZoneProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = AppPalette.forBrightness(isDark);
    final bgColor = palette.background;
    final textColor = palette.ink;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        // THAY ĐỔI: Chuyển title thành nút bấm để chọn coin
        title: GestureDetector(
          onTap: () => _showCoinSelector(context, ref, selectedCoin, isDark),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'BMAG Tracker ($selectedCoin)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Đổi Coin',
            onPressed: () =>
                _showCoinSelector(context, ref, selectedCoin, isDark),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(fractalDataProvider),
          ),
        ],
      ),
      body: NavigationContentFrame(
        child: fractalAsync.when(
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
              color: palette.ink,
              backgroundColor: palette.raised,
              onRefresh: () async => ref.invalidate(fractalDataProvider),
              child: ListView(
                padding: const EdgeInsets.all(AppTokens.space4),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'MA TRẬN ĐỒNG PHA (CONFLUENCE)',
                          softWrap: true,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTokens.space2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.positive,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.space4),
                  ...data.map(
                    (fData) =>
                        _buildFractalRow(context, fData, isDark, timeZoneId),
                  ),
                  const SizedBox(height: 32),
                  _buildLegend(isDark),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFractalRow(
    BuildContext context,
    dynamic data,
    bool isDark,
    String timeZoneId,
  ) {
    final palette = AppPalette.forBrightness(isDark);
    final cardColor = palette.raised;
    final textColor = palette.ink;

    Duration? quarterDuration;
    double progress = 0.0;

    if (data.quarters.length == 4 &&
        data.quarters[0].startTime != null &&
        data.quarters[1].startTime != null) {
      final startTime = data.quarters[0].startTime!;
      quarterDuration = data.quarters[1].startTime!.difference(startTime);
      final endTime = data.quarters[3].startTime!.add(quarterDuration);

      final totalMs = endTime.difference(startTime).inMilliseconds;
      final elapsedMs = AppTimeZone.now(
        timeZoneId,
      ).difference(startTime).inMilliseconds;

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
    final openPriceText = openPrice != null
        ? formatAdaptiveNumber(openPrice.toString())
        : '--';
    final maxHighText = maxHigh != null
        ? formatAdaptiveNumber(maxHigh.toString())
        : '--';
    final minLowText = minLow != null
        ? formatAdaptiveNumber(minLow.toString())
        : '--';
    Widget headerWidget;
    if (data.timeframeLabel == 'M1') {
      final month = ref.watch(selectedMonthProvider);
      headerWidget = Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: textColor, size: 26),
            tooltip: 'Tháng trước',
            onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                DateTime(month.year, month.month - 1),
          ),
          Expanded(
            child: Text(
              'Tháng ${month.month}/${month.year}',
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: textColor,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: textColor, size: 26),
            tooltip: 'Tháng sau',
            onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                DateTime(month.year, month.month + 1),
          ),
        ],
      );
    } else if (data.timeframeLabel == 'Y1') {
      final year = ref.watch(selectedYearProvider);
      headerWidget = Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: textColor, size: 26),
            tooltip: 'Năm trước',
            onPressed: () =>
                ref.read(selectedYearProvider.notifier).state = year - 1,
          ),
          Expanded(
            child: Text(
              'Năm $year',
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: textColor,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: textColor, size: 26),
            tooltip: 'Năm sau',
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
      margin: const EdgeInsets.only(bottom: AppTokens.space4),
      padding: const EdgeInsets.all(AppTokens.space3),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppTokens.radiusLarge),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final currentPrice = Text(
                '\$${formatAdaptiveNumber(data.currentPrice.toString())}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              );
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerWidget,
                    Align(
                      alignment: Alignment.centerRight,
                      child: currentPrice,
                    ),
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: headerWidget),
                  const SizedBox(width: AppTokens.space3),
                  currentPrice,
                ],
              );
            },
          ),
          const SizedBox(height: AppTokens.space2),

          LayoutBuilder(
            builder: (context, constraints) {
              final metricStyle = TextStyle(
                color: palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              );
              if (constraints.maxWidth < 420) {
                Widget compactMetric(
                  String label,
                  String value, {
                  IconData? icon,
                }) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.space1 / 2,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: constraints.maxWidth * 0.48,
                          child: Text(label, style: metricStyle),
                        ),
                        Expanded(
                          child: Text(
                            '${icon == Icons.local_fire_department_outlined
                                ? '🔥 '
                                : icon == Icons.water_drop_outlined
                                ? '💧 '
                                : ''}$value',
                            textAlign: TextAlign.end,
                            softWrap: true,
                            style: metricStyle.copyWith(
                              color:
                                  icon == Icons.local_fire_department_outlined
                                  ? palette.warning
                                  : palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    compactMetric('Mở', openPriceText),
                    compactMetric(
                      'Cao nhất',
                      maxHighText,
                      icon: Icons.local_fire_department_outlined,
                    ),
                    compactMetric(
                      'Thấp nhất',
                      minLowText,
                      icon: Icons.water_drop_outlined,
                    ),
                  ],
                );
              }

              return Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppTokens.space3,
                runSpacing: AppTokens.space2,
                children: [
                  Text('Mở: $openPriceText', style: metricStyle),
                  Text(
                    '🔥 $maxHighText',
                    style: metricStyle.copyWith(color: palette.warning),
                  ),
                  Text(
                    '💧 $minLowText',
                    style: metricStyle.copyWith(color: palette.muted),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppTokens.space4),

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
            Divider(height: 24, color: palette.border),
            Text(
              data.timeframeLabel == 'M1'
                  ? 'Diễn biến từng ngày'
                  : 'Diễn biến từng tháng',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: AppTokens.space3),
            Row(
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
          ],

          const SizedBox(height: AppTokens.space4),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Tiến trình thời gian:',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.space2),
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.space2),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: palette.border,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.ink),
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

    final palette = AppPalette.forBrightness(isDark);
    final isRising = sc.close >= sc.open;
    final color = isRising ? palette.positive : palette.negative;

    double bodyTop = openY < closeY ? openY : closeY;
    double bodyBottom = openY > closeY ? openY : closeY;
    double bodyHeight = bodyBottom - bodyTop;

    if (bodyHeight < 1.0) bodyHeight = 1.0;

    return Semantics(
      label: '${sc.label}: ${isRising ? 'tăng, nến rỗng' : 'giảm, nến đặc'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  child: Container(color: palette.muted),
                ),
                Positioned(
                  top: bodyTop,
                  height: bodyHeight,
                  width: 4.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isRising ? Colors.transparent : color,
                      border: isRising ? Border.all(color: color) : null,
                      borderRadius: BorderRadius.circular(1),
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
              color: palette.muted,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ],
      ),
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

    final palette = AppPalette.forBrightness(isDark);
    final isRising = q.close! >= q.open!;
    final color = isRising ? palette.positive : palette.negative;

    double bodyTop = openY < closeY ? openY : closeY;
    double bodyBottom = openY > closeY ? openY : closeY;
    double bodyHeight = bodyBottom - bodyTop;

    if (bodyHeight < 2.0) {
      bodyHeight = 2.0;
    }

    return Semantics(
      label: '${q.name}: ${isRising ? 'tăng, nến rỗng' : 'giảm, nến đặc'}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: topY,
              height: bottomY - topY,
              width: 1.5,
              child: Container(color: palette.muted),
            ),
            Positioned(
              top: bodyTop,
              height: bodyHeight,
              width: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: isRising ? Colors.transparent : color,
                  border: isRising ? Border.all(color: color) : null,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ],
        ),
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
    final palette = AppPalette.forBrightness(isDark);
    final isEmpty = q.isEmpty;
    final isGreen = q.isGreen;
    final directionColor = isGreen ? palette.positive : palette.negative;

    final blockColor = isEmpty
        ? palette.surface
        : directionColor.withOpacity(0.12);
    final textColor = isEmpty ? palette.muted : directionColor;

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

        const SizedBox(height: AppTokens.space2),

        Semantics(
          label: isEmpty
              ? '${q.name}: không có dữ liệu nến'
              : '${q.name}: ${isGreen ? 'tăng, nến rỗng' : 'giảm, nến đặc'}',
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppTokens.space1 / 2,
            ),
            height: 36,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space1),
            decoration: BoxDecoration(
              color: blockColor,
              borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
              border: isEmpty
                  ? null
                  : Border.all(color: textColor.withOpacity(0.5)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isEmpty) ...[
                      Icon(
                        isGreen ? Icons.trending_up : Icons.trending_down,
                        size: 12,
                        color: textColor,
                      ),
                      const SizedBox(width: AppTokens.space1 / 2),
                    ],
                    Flexible(
                      child: Text(
                        q.name,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (q.hasAbsoluteHigh)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Icon(
                      Icons.local_fire_department_outlined,
                      size: 10,
                      color: palette.warning,
                    ),
                  ),
                if (q.hasAbsoluteLow)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Icon(
                      Icons.water_drop_outlined,
                      size: 10,
                      color: palette.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.space2),

        Text(
          timeStr,
          style: TextStyle(
            fontSize: 9,
            color: palette.muted,
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
    final palette = AppPalette.forBrightness(isDark);
    final tColor = palette.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HƯỚNG DẪN XEM:',
          style: TextStyle(
            color: tColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppTokens.space2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 16,
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.positive, width: 1.5),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: AppTokens.space1),
                Expanded(
                  child: Text(
                    'Tăng: nến rỗng',
                    style: TextStyle(color: tColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space2),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 16,
                  decoration: BoxDecoration(
                    color: palette.negative,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: AppTokens.space1),
                Expanded(
                  child: Text('Giảm: nến đặc', style: TextStyle(color: tColor)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space2),
        Row(
          children: [
            Icon(Icons.local_fire_department_outlined, color: palette.warning),
            const SizedBox(width: AppTokens.space1),
            Expanded(
              child: Text(
                'Cực đại (Đỉnh cao nhất của khung)',
                style: TextStyle(color: tColor, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space1),
        Row(
          children: [
            Icon(Icons.water_drop_outlined, color: palette.muted),
            const SizedBox(width: AppTokens.space1),
            Expanded(
              child: Text(
                'Cực tiểu (Đáy thấp nhất của khung)',
                style: TextStyle(color: tColor, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space1),
        Text(
          'Biểu đồ nến dọc thể hiện độ dài ngắn (biên độ giá) của từng phân đoạn thời gian nhỏ.',
          style: TextStyle(color: tColor, fontSize: 12),
        ),
      ],
    );
  }

  // THÊM MỚI: Popup Dialog để tìm và chọn Coin
  void _showCoinSelector(
    BuildContext context,
    WidgetRef ref,
    String currentCoin,
    bool isDark,
  ) {
    final textController = TextEditingController(text: currentCoin);
    // Danh sách gợi ý nhanh
    final commonCoins = [
      'BTC',
      'ETH',
      'SOL',
      'BNB',
      'XRP',
      'SUI',
      'PEPE',
      'DOGE',
      'LINK',
    ];

    showDialog(
      context: context,
      builder: (context) {
        final palette = AppPalette.forBrightness(isDark);
        return AlertDialog(
          backgroundColor: palette.raised,
          title: Text(
            'Chọn Coin',
            style: TextStyle(
              color: palette.ink,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: textController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Nhập mã (VD: APT, ARB...)',
                    hintStyle: TextStyle(color: palette.muted),
                    suffixText: '-USDT',
                    suffixStyle: TextStyle(color: palette.muted),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: palette.ink),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.space5),
                Text(
                  'Gợi ý nhanh:',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
                const SizedBox(height: AppTokens.space2),
                Wrap(
                  spacing: AppTokens.space2,
                  runSpacing: AppTokens.space2,
                  children: commonCoins.map((coin) {
                    return InkWell(
                      onTap: () {
                        ref.read(selectedCoinProvider.notifier).state = coin;
                        Navigator.pop(context);
                      },
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.space3,
                          vertical: AppTokens.space2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusSmall,
                          ),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          coin,
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Huỷ', style: TextStyle(color: palette.ink)),
            ),
            ElevatedButton(
              onPressed: () {
                final newCoin = textController.text.trim().toUpperCase();
                if (newCoin.isNotEmpty) {
                  ref.read(selectedCoinProvider.notifier).state = newCoin;
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.ink,
                foregroundColor: palette.onStrong,
              ),
              child: const Text(
                'Đồng ý',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}
