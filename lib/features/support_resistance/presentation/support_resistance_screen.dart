import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/adaptive_number_format.dart';
import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../data/watchlist_store.dart';
import '../domain/models.dart';
import 'providers/levels_provider.dart';
import 'providers/watchlist_provider.dart';

class SupportResistanceScreen extends ConsumerStatefulWidget {
  const SupportResistanceScreen({super.key});

  @override
  ConsumerState<SupportResistanceScreen> createState() =>
      _SupportResistanceScreenState();
}

class _SupportResistanceScreenState
    extends ConsumerState<SupportResistanceScreen> {
  String? _lastSelectionSignature;
  bool _isRefreshing = false;

  Future<void> _refreshLevels() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await ref.read(supportResistanceLevelsProvider).refresh();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchlist = ref.watch(supportResistanceWatchlistProvider);
    final levels = ref.watch(supportResistanceLevelsProvider);
    final selection = watchlist.snapshot;
    final instrumentIds = selection.instrumentIdsFor(selection.marketMode);
    final keys = instrumentIds
        .map(
          (instrumentId) => SupportResistanceLevelsKey(
            marketMode: selection.marketMode,
            instrumentId: instrumentId,
            timeframe: selection.timeframe,
          ),
        )
        .toList(growable: false);
    final signature = <Object>[
      selection.marketMode,
      selection.timeframe,
      ...instrumentIds,
    ].join('|');
    if (signature != _lastSelectionSignature) {
      _lastSelectionSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(supportResistanceLevelsProvider).setActiveKeys(keys);
        }
      });
    }

    final theme = Theme.of(context);
    return NavigationContentFrame(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hỗ trợ và kháng cự',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ManualRefreshButton(
                      buttonKey: const Key('support-resistance-refresh'),
                      onRefresh: instrumentIds.isEmpty ? null : _refreshLevels,
                      isBusy:
                          _isRefreshing ||
                          keys.any(
                            (key) =>
                                levels.stateFor(key)?.status ==
                                SupportResistanceLevelsStatus.loading,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Thị trường',
                  child: SegmentedButton<SupportResistanceMarketMode>(
                    segments:
                        const <ButtonSegment<SupportResistanceMarketMode>>[
                          ButtonSegment(
                            value: SupportResistanceMarketMode.spot,
                            label: Text('Spot'),
                            icon: Icon(Icons.currency_exchange),
                          ),
                          ButtonSegment(
                            value: SupportResistanceMarketMode.perpetual,
                            label: Text('Perpetual'),
                            icon: Icon(Icons.swap_vert),
                          ),
                        ],
                    selected: <SupportResistanceMarketMode>{
                      selection.marketMode,
                    },
                    onSelectionChanged: (selected) {
                      if (selected.isNotEmpty) {
                        unawaited(watchlist.setMarketMode(selected.first));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Khung thời gian',
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final timeframe in SupportResistanceTimeframe.values)
                        ChoiceChip(
                          key: Key('timeframe-${timeframe.label}'),
                          label: Text(timeframe.label),
                          selected: selection.timeframe == timeframe,
                          onSelected: (_) =>
                              unawaited(watchlist.setTimeframe(timeframe)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${selection.marketMode == SupportResistanceMarketMode.spot ? 'Spot' : 'Perpetual'} · ${selection.timeframe.label} · ${instrumentIds.length}/10 coin',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      key: const Key('support-resistance-add'),
                      tooltip: 'Thêm coin',
                      onPressed: () =>
                          _openInstrumentPicker(selection.marketMode),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                if (watchlist.saveError case final saveError?) ...[
                  const SizedBox(height: 4),
                  MaterialBanner(
                    content: Text(saveError),
                    actions: [
                      TextButton(
                        onPressed: watchlist.clearSaveError,
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                ],
                if (watchlist.loadError case final loadError?) ...[
                  const SizedBox(height: 12),
                  Text(
                    loadError,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  TextButton(
                    onPressed: () => unawaited(watchlist.load()),
                    child: const Text('Thử lại'),
                  ),
                ],
                if (instrumentIds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.stacked_line_chart,
                            size: 40,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Chọn coin để bắt đầu',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Thêm tối đa 10 cặp USDT đang giao dịch.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final instrumentId in instrumentIds)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _CoinLevelsCard(
                        key: ValueKey('support-resistance-card-$instrumentId'),
                        marketMode: selection.marketMode,
                        instrumentId: instrumentId,
                        timeframe: selection.timeframe,
                        state: levels.stateFor(
                          SupportResistanceLevelsKey(
                            marketMode: selection.marketMode,
                            instrumentId: instrumentId,
                            timeframe: selection.timeframe,
                          ),
                        ),
                        onRemove: () =>
                            unawaited(watchlist.removeInstrument(instrumentId)),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openInstrumentPicker(SupportResistanceMarketMode marketMode) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) =>
            _SupportResistanceInstrumentPicker(marketMode: marketMode),
      );
}

class _CoinLevelsCard extends StatelessWidget {
  const _CoinLevelsCard({
    super.key,
    required this.marketMode,
    required this.instrumentId,
    required this.timeframe,
    required this.state,
    required this.onRemove,
  });

  final SupportResistanceMarketMode marketMode;
  final String instrumentId;
  final SupportResistanceTimeframe timeframe;
  final SupportResistanceLevelsState? state;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = state?.snapshot;
    final isLoading = state?.status == SupportResistanceLevelsStatus.loading;
    final isUnavailable =
        state?.status == SupportResistanceLevelsStatus.unavailable;
    final stale = state?.isStale ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    instrumentId,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('remove-instrument-$instrumentId'),
                  tooltip: 'Xóa $instrumentId',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              '${marketMode == SupportResistanceMarketMode.spot ? 'Spot' : 'Perpetual'} · ${timeframe.label}',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            if (isLoading && snapshot == null)
              const Text('Đang tải dữ liệu…', key: Key('levels-loading'))
            else if (snapshot == null)
              Text(
                'Dữ liệu không khả dụng',
                key: Key('levels-unavailable-$instrumentId'),
                style: TextStyle(color: theme.colorScheme.error),
              )
            else ...[
              Text(
                'Giá hiện tại: ${formatSupportResistancePrice(snapshot.referencePrice)}',
              ),
              const SizedBox(height: 4),
              Text('Cập nhật: ${_utcTimestamp(snapshot.fetchedAt)} UTC'),
              if (isLoading)
                const Text(
                  'Đang cập nhật · dữ liệu cũ',
                  key: Key('levels-stale'),
                )
              else if (stale || isUnavailable)
                Text(
                  'Dữ liệu cũ · lần cập nhật thất bại',
                  key: const Key('levels-stale'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (isUnavailable)
                Text(
                  'Không thể cập nhật dữ liệu cho $instrumentId',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (snapshot.candles.length < 300 ||
                  snapshot.analysis.supports.length < 5 ||
                  snapshot.analysis.resistances.length < 5)
                Text(
                  'Dữ liệu thưa · ${snapshot.candles.length}/300 nến',
                  key: Key('levels-sparse-$instrumentId'),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LevelColumn(
                      instrumentId: instrumentId,
                      prefix: 'support',
                      title: 'Hỗ trợ (${snapshot.analysis.supports.length})',
                      levels: snapshot.analysis.supports,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LevelColumn(
                      instrumentId: instrumentId,
                      prefix: 'resistance',
                      title:
                          'Kháng cự (${snapshot.analysis.resistances.length})',
                      levels: snapshot.analysis.resistances,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelColumn extends StatelessWidget {
  const _LevelColumn({
    required this.instrumentId,
    required this.prefix,
    required this.title,
    required this.levels,
  });

  final String instrumentId;
  final String prefix;
  final String title;
  final List<SupportResistanceLevel> levels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        if (levels.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Chưa có mức'),
          )
        else
          for (var index = 0; index < levels.length && index < 5; index++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                formatSupportResistancePrice(levels[index].price),
                key: Key('$prefix-level-$instrumentId-$index'),
                semanticsLabel:
                    '$title ${index + 1}: ${formatSupportResistancePrice(levels[index].price)}',
              ),
            ),
      ],
    );
  }
}

class _SupportResistanceInstrumentPicker extends ConsumerStatefulWidget {
  const _SupportResistanceInstrumentPicker({required this.marketMode});

  final SupportResistanceMarketMode marketMode;

  @override
  ConsumerState<_SupportResistanceInstrumentPicker> createState() =>
      _SupportResistanceInstrumentPickerState();
}

class _SupportResistanceInstrumentPickerState
    extends ConsumerState<_SupportResistanceInstrumentPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instruments = ref.watch(
      supportResistanceInstrumentsProvider(widget.marketMode),
    );
    final watchlist = ref.watch(supportResistanceWatchlistProvider);
    final selectedIds = watchlist.snapshot.instrumentIdsFor(widget.marketMode);
    final atLimit =
        selectedIds.length >= WatchlistSnapshot.maximumSelectionsPerMode;

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chọn coin ${widget.marketMode == SupportResistanceMarketMode.spot ? 'Spot' : 'Perpetual'}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('support-resistance-picker-close'),
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              key: const Key('support-resistance-coin-search'),
              decoration: const InputDecoration(
                labelText: 'Tìm coin hoặc cặp USDT',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 8),
            Text('${selectedIds.length}/10 đã chọn'),
            const SizedBox(height: 8),
            Expanded(
              child: instruments.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Không tải được danh sách coin đang giao dịch.',
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          supportResistanceInstrumentsProvider(
                            widget.marketMode,
                          ),
                        ),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
                data: (activeInstruments) {
                  final query = _query.toUpperCase();
                  final matches = activeInstruments
                      .where(
                        (instrument) =>
                            query.isEmpty ||
                            instrument.instrumentId.contains(query) ||
                            instrument.baseCurrency.contains(query),
                      )
                      .toList(growable: false);
                  if (matches.isEmpty) {
                    return const Center(child: Text('Không tìm thấy coin.'));
                  }
                  return ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final instrument = matches[index];
                      final isSelected = selectedIds.contains(
                        instrument.instrumentId,
                      );
                      return ListTile(
                        key: Key(
                          'instrument-option-${instrument.instrumentId}',
                        ),
                        title: Text(instrument.instrumentId),
                        subtitle: Text(instrument.baseCurrency),
                        trailing: IconButton(
                          tooltip: isSelected
                              ? 'Xóa ${instrument.instrumentId}'
                              : 'Thêm ${instrument.instrumentId}',
                          onPressed: !isSelected && atLimit
                              ? null
                              : () => unawaited(
                                  isSelected
                                      ? watchlist.removeInstrument(
                                          instrument.instrumentId,
                                          marketMode: widget.marketMode,
                                        )
                                      : watchlist.addInstrument(
                                          instrument.instrumentId,
                                        ),
                                ),
                          icon: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        onTap: !isSelected && atLimit
                            ? null
                            : () => unawaited(
                                isSelected
                                    ? watchlist.removeInstrument(
                                        instrument.instrumentId,
                                        marketMode: widget.marketMode,
                                      )
                                    : watchlist.addInstrument(
                                        instrument.instrumentId,
                                      ),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatSupportResistancePrice(double value) {
  if (!value.isFinite || value <= 0) return '--';
  final adaptive = formatAdaptiveNumber(value.toString());
  final renderedNumber = double.tryParse(adaptive.replaceAll(',', ''));
  return renderedNumber == null || renderedNumber == 0
      ? value.toString()
      : adaptive;
}

String _utcTimestamp(DateTime timestamp) => timestamp
    .toUtc()
    .toIso8601String()
    .replaceFirst('T', ' ')
    .replaceFirst('Z', '');
