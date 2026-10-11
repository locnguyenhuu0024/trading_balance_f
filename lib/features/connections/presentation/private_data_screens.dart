import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/backend_data_client.dart';
import '../../../core/network/foreground_read_gate.dart';
import '../../../core/session/connection_scope.dart';
import '../../../core/session/user_session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../portfolio/presentation/portfolio_screen.dart'
    show hideBalanceProvider;
import '../data/multi_user_api_client.dart';
import '../domain/connection_models.dart';
import '../../strategy/data/strategy_api_client.dart';
import '../../strategy/presentation/strategy_screen.dart';
import 'connections_page.dart';
import 'providers/multi_user_provider.dart';

final scopedBalancesProvider = FutureProvider.autoDispose
    .family<ScopedPage<NormalizedBalance>, ConnectionScope>((ref, scope) {
      final api = ref.read(multiUserApiClientProvider);
      return _withForegroundReadLease(
        ref,
        scope,
        requestKey: 'balances',
        load: (cancel) => api.allBalances(scope, cancelToken: cancel),
      );
    });

final scopedPositionsProvider = FutureProvider.autoDispose
    .family<ScopedPage<NormalizedPosition>, ConnectionScope>((ref, scope) {
      final api = ref.read(multiUserApiClientProvider);
      return _withForegroundReadLease(
        ref,
        scope,
        requestKey: 'positions',
        load: (cancel) => api.allPositions(scope, cancelToken: cancel),
      );
    });

final scopedOrdersProvider = FutureProvider.autoDispose
    .family<ScopedPage<NormalizedOrder>, ConnectionScope>((ref, scope) {
      final api = ref.read(multiUserApiClientProvider);
      return _withForegroundReadLease(
        ref,
        scope,
        requestKey: 'orders',
        load: (cancel) => api.allOrders(scope, cancelToken: cancel),
      );
    });

@immutable
class MultiAccountBalanceEntry {
  const MultiAccountBalanceEntry({
    required this.connection,
    required this.product,
    this.snapshot,
    this.unavailable = false,
  });

  final ConnectionRecord connection;
  final String product;
  final ScopedPage<NormalizedBalance>? snapshot;
  final bool unavailable;

  bool get partial {
    final page = snapshot?.page;
    return page == null ||
        page.nextCursor != null ||
        page.meta.stale ||
        !page.meta.complete;
  }
}

@immutable
class MultiAccountBalanceOverview {
  const MultiAccountBalanceOverview({
    required this.entries,
    required this.scannedConnections,
    required this.totalConnections,
    required this.requestedPages,
    required this.omittedConnections,
  });

  final List<MultiAccountBalanceEntry> entries;
  final int scannedConnections;
  final int totalConnections;
  final int requestedPages;
  final int omittedConnections;
}

final multiAccountBalanceOverviewProvider =
    FutureProvider.autoDispose<MultiAccountBalanceOverview>((ref) async {
      final isForeground = ref.watch(
        multiUserAppForegroundProvider.select((state) => state.isForeground),
      );
      if (!isForeground) {
        throw const BackendDataException(
          code: 'request_cancelled',
          message: 'Đã tạm dừng tổng quan khi ứng dụng ở nền.',
        );
      }
      final sessions = ref.watch(userSessionStoreProvider);
      final owner = sessions.current;
      final ownerGeneration = sessions.generation;
      if (owner == null || !owner.canReadPrivate) {
        throw const BackendDataException(
          code: 'authentication_required',
          message: 'Phiên máy chủ không còn hiệu lực.',
          statusCode: 401,
        );
      }
      var callerActive = true;
      final cancellation = CancelToken();
      final scopes = ConnectionScopeStore();
      final projectionSessions = UserSessionStore(initialSession: owner);
      void invalidateProjectionOwner() {
        if (sessions.hasSameOwner(owner)) return;
        callerActive = false;
        cancellation.cancel('The overview session owner changed.');
        projectionSessions.update(null);
      }

      sessions.addListener(invalidateProjectionOwner);
      ref.onDispose(() {
        callerActive = false;
        cancellation.cancel('The overview owner or consumer changed.');
        sessions.removeListener(invalidateProjectionOwner);
        projectionSessions.update(null);
        projectionSessions.dispose();
        scopes.dispose();
      });
      final api = ref.read(multiUserApiClientProvider);
      final readOnlyApi = api.createReadOnlyScopeReader(
        scopes,
        isolatedSessions: projectionSessions,
      );
      final connections = await api.getConnections(cancelToken: cancellation);
      if (!callerActive || !sessions.matches(ownerGeneration, owner)) {
        throw const BackendDataException(
          code: 'scope_changed',
          message: 'Phiên đã thay đổi. Hãy tải lại tổng quan.',
          statusCode: 409,
        );
      }

      const maximumConnections = 8;
      final entries = <MultiAccountBalanceEntry>[];
      var requestedPages = 0;
      final boundedConnections = connections.take(maximumConnections).toList();
      for (final connection in boundedConnections) {
        final products = _productsForOverview(connection.exchange);
        for (final product in products) {
          if (!callerActive || !sessions.matches(ownerGeneration, owner)) {
            throw const BackendDataException(
              code: 'scope_changed',
              message: 'Phiên đã thay đổi. Hãy tải lại tổng quan.',
              statusCode: 409,
            );
          }
          if (!connection.isAvailable) {
            entries.add(
              MultiAccountBalanceEntry(
                connection: connection,
                product: product,
                unavailable: true,
              ),
            );
            continue;
          }
          final scope = scopes.select(
            session: owner,
            connectionId: connection.connectionId,
            exchange: connection.exchange,
            environment: connection.environment,
            region: connection.region,
            product: product,
            credentialVersion: connection.credentialVersion,
            permissionVersion: connection.permissionVersion,
          );
          if (scope == null) {
            entries.add(
              MultiAccountBalanceEntry(
                connection: connection,
                product: product,
                unavailable: true,
              ),
            );
            continue;
          }
          try {
            requestedPages++;
            final result = await readOnlyApi.balances(
              scope,
              limit: 100,
              cancelToken: cancellation,
            );
            if (!callerActive ||
                !sessions.matches(ownerGeneration, owner) ||
                !scopes.matches(scope.generation, scope) ||
                !result.scope.sameAuthority(scope)) {
              throw const BackendDataException(
                code: 'scope_changed',
                message: 'Phiên hoặc kết nối đã thay đổi.',
                statusCode: 409,
              );
            }
            entries.add(
              MultiAccountBalanceEntry(
                connection: connection,
                product: product,
                snapshot: result,
              ),
            );
          } on BackendDataException catch (error) {
            if (error.statusCode == 409 ||
                error.code == 'session_changed' ||
                error.code == 'scope_changed' ||
                ((error.statusCode == 401 ||
                        error.code == 'authentication_required') &&
                    (!callerActive ||
                        !sessions.matches(ownerGeneration, owner)))) {
              rethrow;
            }
            entries.add(
              MultiAccountBalanceEntry(
                connection: connection,
                product: product,
                unavailable: true,
              ),
            );
          } catch (_) {
            entries.add(
              MultiAccountBalanceEntry(
                connection: connection,
                product: product,
                unavailable: true,
              ),
            );
          }
        }
      }
      if (!callerActive || !sessions.matches(ownerGeneration, owner)) {
        throw const BackendDataException(
          code: 'scope_changed',
          message: 'Phiên đã thay đổi. Hãy tải lại tổng quan.',
          statusCode: 409,
        );
      }
      return MultiAccountBalanceOverview(
        entries: List.unmodifiable(entries),
        scannedConnections: boundedConnections.length,
        totalConnections: connections.length,
        requestedPages: requestedPages,
        omittedConnections: math.max(
          0,
          connections.length - maximumConnections,
        ),
      );
    });

List<String> _productsForOverview(String exchange) => switch (exchange) {
  'OKX' => const ['SPOT', 'MARGIN', 'SWAP', 'FUTURES'],
  'BINANCE' => const ['SPOT', 'USD_M'],
  _ => const [],
};

Future<ScopedPage<T>> _withForegroundReadLease<T>(
  Ref ref,
  ConnectionScope scope, {
  required String requestKey,
  required Future<ScopedPage<T>> Function(CancelToken token) load,
}) async {
  final isForeground = ref.watch(
    multiUserAppForegroundProvider.select((state) => state.isForeground),
  );
  if (!isForeground) {
    throw const BackendDataException(
      code: 'request_cancelled',
      message: 'Đã tạm dừng cập nhật khi ứng dụng ở nền.',
    );
  }
  final sessions = ref.watch(userSessionStoreProvider);
  final session = sessions.current;
  final sessionGeneration = sessions.generation;
  final scopes = ref.watch(connectionScopeStoreProvider);
  if (session == null ||
      !session.canReadPrivate ||
      !scopes.matches(scope.generation, scope)) {
    throw const BackendDataException(
      code: 'scope_changed',
      message: 'Phiên hoặc tài khoản đã thay đổi. Hãy tải lại dữ liệu.',
      statusCode: 409,
    );
  }
  final gate = ref.read(multiUserForegroundReadGateProvider);
  var callerActive = true;
  final lease = gate.acquire<ScopedPage<T>>(
    sessionIdentity: sessions,
    generation: sessionGeneration,
    requestKey: '${scope.connectionId}:${scope.product}:$requestKey',
    canStart: () =>
        callerActive &&
        ref.read(multiUserAppForegroundProvider).isForeground &&
        sessions.matches(sessionGeneration, session) &&
        scopes.matches(scope.generation, scope),
    load: load,
    isTransientFailure: _isTransientPrivateReadFailure,
    isCancellationFailure: _isPrivateReadCancellation,
    retryAfter: _privateReadRetryAfter,
  );
  ref.onDispose(() {
    callerActive = false;
    lease.release();
  });
  final result = await lease.future;
  if (!callerActive ||
      !sessions.matches(sessionGeneration, session) ||
      !scopes.matches(scope.generation, scope) ||
      !result.scope.sameAuthority(scope)) {
    throw const BackendDataException(
      code: 'scope_changed',
      message: 'Phiên hoặc tài khoản đã thay đổi. Hãy tải lại dữ liệu.',
      statusCode: 409,
    );
  }
  return result;
}

bool _isTransientPrivateReadFailure(Object error) {
  if (error is BackendDataException) {
    final status = error.statusCode;
    return status == 408 ||
        status == 425 ||
        status == 429 ||
        (status != null && status >= 500) ||
        error.code == 'network_error';
  }
  return false;
}

bool _isPrivateReadCancellation(Object error) =>
    error is BackendDataException && error.code == 'request_cancelled';

Duration? _privateReadRetryAfter(Object error, DateTime now) {
  if (error is BackendDataException && error.statusCode == 429) {
    return ForegroundReadGate.parseRetryAfter(error.retryAfter, now);
  }
  return null;
}

class MultiUserPortfolioScreen extends ConsumerStatefulWidget {
  const MultiUserPortfolioScreen({super.key});

  @override
  ConsumerState<MultiUserPortfolioScreen> createState() =>
      _MultiUserPortfolioScreenState();
}

class _MultiUserPortfolioScreenState
    extends ConsumerState<MultiUserPortfolioScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _showCombinedOverview = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumePolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumePolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _resumePolling() {
    _pollTimer?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _pollTimer = null;
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _showCombinedOverview) return;
      final scope = ref.read(connectionScopeStoreProvider).current;
      if (scope == null) return;
      ref.invalidate(scopedPositionsProvider(scope));
      ref.invalidate(scopedOrdersProvider(scope));
      _pollCount++;
      if (_pollCount % 3 == 0) {
        ref.invalidate(scopedBalancesProvider(scope));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(
      connectionScopeStoreProvider.select((store) => store.current),
    );
    final hidden = ref.watch(hideBalanceProvider);
    final positions = scope == null
        ? null
        : ref.watch(scopedPositionsProvider(scope));
    final orders = scope == null
        ? null
        : ref.watch(scopedOrdersProvider(scope));
    return Scaffold(
      appBar: AppBar(
        title: Text(_showCombinedOverview ? 'Tổng quan kết nối' : 'Tài sản'),
        actions: [
          if (MediaQuery.sizeOf(context).width < 600)
            IconButton(
              key: const Key('toggle-combined-overview'),
              tooltip: _showCombinedOverview ? 'Tài sản' : 'Nhiều kết nối',
              constraints: const BoxConstraints(
                minWidth: AppTokens.minimumTouchTarget,
                minHeight: AppTokens.minimumTouchTarget,
              ),
              onPressed: () => setState(
                () => _showCombinedOverview = !_showCombinedOverview,
              ),
              icon: Icon(
                _showCombinedOverview
                    ? Icons.account_balance_wallet_outlined
                    : Icons.account_tree_outlined,
              ),
            )
          else
            TextButton.icon(
              key: const Key('toggle-combined-overview'),
              onPressed: () => setState(
                () => _showCombinedOverview = !_showCombinedOverview,
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, AppTokens.minimumTouchTarget),
              ),
              icon: Icon(
                _showCombinedOverview
                    ? Icons.account_balance_wallet_outlined
                    : Icons.account_tree_outlined,
              ),
              label: Text(_showCombinedOverview ? 'Tài sản' : 'Nhiều kết nối'),
            ),
          if (_showCombinedOverview)
            ManualRefreshButton(
              buttonKey: const Key('combined-overview-refresh'),
              onRefresh: () async =>
                  ref.invalidate(multiAccountBalanceOverviewProvider),
              isBusy: ref.watch(multiAccountBalanceOverviewProvider).isLoading,
            )
          else
            ManualRefreshButton(
              buttonKey: const Key('portfolio-v2-refresh'),
              onRefresh: scope == null
                  ? null
                  : () async {
                      ref.invalidate(scopedBalancesProvider(scope));
                      ref.invalidate(scopedPositionsProvider(scope));
                      ref.invalidate(scopedOrdersProvider(scope));
                    },
              isBusy:
                  scope != null &&
                  ref.watch(scopedBalancesProvider(scope)).isLoading,
            ),
        ],
      ),
      body: _showCombinedOverview
          ? _CombinedBalanceOverviewPage(hidden: hidden)
          : scope == null
          ? const _NoScopeState()
          : ref
                .watch(scopedBalancesProvider(scope))
                .when(
                  loading: () => const _LoadingState(label: 'Đang tải số dư…'),
                  error: (error, _) => _ErrorState(
                    message: _safeError(error),
                    onRetry: () =>
                        ref.invalidate(scopedBalancesProvider(scope)),
                  ),
                  data: (result) => _BalancePage(
                    page: result.page,
                    hidden: hidden,
                    positions: positions,
                    orders: orders,
                  ),
                ),
    );
  }
}

class _CombinedBalanceOverviewPage extends ConsumerWidget {
  const _CombinedBalanceOverviewPage({required this.hidden});

  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return ref
        .watch(multiAccountBalanceOverviewProvider)
        .when(
          loading: () =>
              const _LoadingState(label: 'Đang tải số dư từng kết nối…'),
          error: (error, _) => _ErrorState(
            message: _safeError(error),
            onRetry: () => ref.invalidate(multiAccountBalanceOverviewProvider),
          ),
          data: (overview) {
            final grouped = <String, List<MultiAccountBalanceEntry>>{};
            for (final entry in overview.entries) {
              grouped
                  .putIfAbsent(entry.connection.connectionId, () => [])
                  .add(entry);
            }
            return ListView(
              key: const Key('combined-balance-overview-list'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.space4,
                    AppTokens.space3,
                    AppTokens.space4,
                    AppTokens.space1,
                  ),
                  child: Text(
                    'Số dư được giữ theo từng sàn và đơn vị gốc. Không có tổng quy đổi chung khi chưa có tỷ giá và thời điểm định giá chung đã xác minh.',
                    style: TextStyle(color: palette.muted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.space4,
                    vertical: AppTokens.space1,
                  ),
                  child: Text(
                    'Kết nối được xét ${overview.scannedConnections}/${overview.totalConnections} · Trang số dư đã yêu cầu ${overview.requestedPages}.',
                    key: const Key('combined-overview-coverage'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (overview.omittedConnections > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.space4,
                      vertical: AppTokens.space1,
                    ),
                    child: Text(
                      '${overview.omittedConnections} kết nối chưa được xét do giới hạn mỗi lần tải.',
                      key: const Key('combined-overview-omitted'),
                      style: TextStyle(color: palette.muted),
                    ),
                  ),
                for (final entries in grouped.values)
                  Card(
                    margin: const EdgeInsets.fromLTRB(
                      AppTokens.space3,
                      AppTokens.space1,
                      AppTokens.space3,
                      AppTokens.space1,
                    ),
                    child: ExpansionTile(
                      key: Key(
                        'overview-connection-${entries.first.connection.connectionId}',
                      ),
                      title: Text(entries.first.connection.displayName),
                      subtitle: Text(
                        '${entries.first.connection.exchange} · ${entries.first.connection.environment} ${entries.first.connection.region} · ${entries.length} sản phẩm',
                      ),
                      children: [
                        for (final entry in entries)
                          _OverviewProductEntry(entry: entry, hidden: hidden),
                      ],
                    ),
                  ),
                if (grouped.isEmpty)
                  const _CenteredNotice(
                    icon: Icons.account_balance_outlined,
                    text: 'Chưa có kết nối được hỗ trợ để đọc số dư.',
                  ),
              ],
            );
          },
        );
  }
}

class _OverviewProductEntry extends StatelessWidget {
  const _OverviewProductEntry({required this.entry, required this.hidden});

  final MultiAccountBalanceEntry entry;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final page = entry.snapshot?.page;
    final status = entry.unavailable
        ? 'Không có dữ liệu · không tính vào tổng'
        : page == null
        ? 'Không có snapshot'
        : [
            if (page.nextCursor != null)
              'Còn trang tiếp · đang hiển thị trang đầu',
            if (page.meta.stale) 'Snapshot cũ · cần tải lại',
            if (!page.meta.complete) 'Snapshot chưa đầy đủ',
            if (page.nextCursor == null &&
                !page.meta.stale &&
                page.meta.complete)
              'Snapshot riêng của ${entry.product}',
          ].join(' · ');
    final rows = entry.snapshot?.page.rows ?? const <NormalizedBalance>[];
    return ExpansionTile(
      key: Key(
        'overview-product-${entry.connection.connectionId}-${entry.product}',
      ),
      title: Text('${entry.product} · ${rows.length} tài sản trên trang'),
      subtitle: Text(status),
      children: [
        if (entry.unavailable || page == null)
          const ListTile(
            title: Text('Không có snapshot số dư'),
            subtitle: Text('Giá trị không khả dụng; không thay bằng 0.'),
          )
        else if (rows.isEmpty)
          const ListTile(title: Text('Trang này chưa có tài sản.'))
        else
          for (final row in rows) _OverviewBalanceRow(row: row, hidden: hidden),
      ],
    );
  }
}

class _OverviewBalanceRow extends StatelessWidget {
  const _OverviewBalanceRow({required this.row, required this.hidden});

  final NormalizedBalance row;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final asset = row.asset.isEmpty ? 'Tài sản' : row.asset;
    final unit = row.unit.isEmpty ? row.asset : row.unit;
    String amount(String? value) => value == null
        ? 'không có dữ liệu'
        : hidden
        ? '•••••• ${unit.isEmpty ? '' : unit}'
        : '$value${unit.isEmpty ? '' : ' $unit'}';
    return ListTile(
      title: Text(asset),
      subtitle: Text(
        'Khả dụng ${amount(row.available)} · Khóa ${amount(row.locked)} · Tổng ${amount(row.total)}',
      ),
    );
  }
}

class _BalancePage extends StatelessWidget {
  const _BalancePage({
    required this.page,
    required this.hidden,
    required this.positions,
    required this.orders,
  });
  final NormalizedPage<NormalizedBalance> page;
  final bool hidden;
  final AsyncValue<ScopedPage<NormalizedPosition>>? positions;
  final AsyncValue<ScopedPage<NormalizedOrder>>? orders;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final compactBalances =
        MediaQuery.sizeOf(context).width < 480 ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return CustomScrollView(
      key: const Key('normalized-balance-list'),
      slivers: [
        SliverToBoxAdapter(child: _DataQualityBanner(meta: page.meta)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.space4,
              AppTokens.space2,
              AppTokens.space4,
              AppTokens.space2,
            ),
            child: Text(
              'Tổng quan kết nối · số dư theo đơn vị gốc. Không quy đổi sang tiền pháp định khi thiếu tỷ giá chung đã xác minh.',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
            child: Row(
              children: [
                Expanded(
                  child: _OverviewCount(label: 'Vị thế mở', value: positions),
                ),
                const SizedBox(width: AppTokens.space2),
                Expanded(
                  child: _OverviewCount(label: 'Lệnh', value: orders),
                ),
              ],
            ),
          ),
        ),
        if (page.rows.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _CenteredNotice(
              icon: Icons.account_balance_wallet_outlined,
              text: 'Máy chủ chưa trả về tài sản cho sản phẩm này.',
            ),
          )
        else
          SliverPadding(
            key: const Key('normalized-balance-rows'),
            padding: const EdgeInsets.symmetric(vertical: AppTokens.space1),
            sliver: SliverList.builder(
              itemCount: page.rows.length,
              itemBuilder: (context, index) {
                final row = page.rows[index];
                final unit = row.unit.isEmpty ? row.asset : row.unit;
                final leading = CircleAvatar(
                  backgroundColor: palette.surface,
                  child: Text(
                    row.asset.isEmpty ? '?' : row.asset.characters.first,
                    style: TextStyle(color: palette.ink),
                  ),
                );
                final title = row.asset.isEmpty ? 'Tài sản' : row.asset;
                return Card(
                  margin: const EdgeInsets.fromLTRB(
                    AppTokens.space4,
                    AppTokens.space1,
                    AppTokens.space4,
                    AppTokens.space1,
                  ),
                  child: compactBalances
                      ? Padding(
                          padding: const EdgeInsets.all(AppTokens.space3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  leading,
                                  const SizedBox(width: AppTokens.space3),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppTokens.space2),
                              Padding(
                                padding: const EdgeInsets.only(left: 48),
                                child: hidden
                                    ? const Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Khả dụng •••'),
                                          Text('Khóa •••'),
                                          Text(
                                            'Tổng •••',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Khả dụng ${row.available ?? '—'} $unit',
                                          ),
                                          Text(
                                            'Khóa ${row.locked ?? '—'} $unit',
                                          ),
                                          Text(
                                            'Tổng ${row.total ?? '—'} $unit',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        )
                      : ListTile(
                          minVerticalPadding: AppTokens.space2,
                          leading: leading,
                          title: Text(title),
                          subtitle: Text(
                            hidden
                                ? 'Khả dụng ••• · Khóa •••'
                                : 'Khả dụng ${row.available ?? '—'} $unit · Khóa ${row.locked ?? '—'} $unit',
                          ),
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 132),
                            child: Text(
                              hidden ? '••••••' : '${row.total ?? '—'} $unit',
                              textAlign: TextAlign.end,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _OverviewCount extends StatelessWidget {
  const _OverviewCount({required this.label, required this.value});
  final String label;
  final AsyncValue<dynamic>? value;

  @override
  Widget build(BuildContext context) {
    final state = value;
    final text = state == null
        ? 'Chưa chọn'
        : state.when(
            loading: () => 'Đang tải…',
            error: (_, _) => 'Chưa khả dụng',
            data: (page) {
              if (page is! ScopedPage) return 'Chưa khả dụng';
              final rows = page.page.rows;
              final qualifier = !page.page.meta.complete || page.page.meta.stale
                  ? ' · một phần'
                  : '';
              return '${rows.length}$qualifier';
            },
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppPalette.of(context).muted)),
            const SizedBox(height: AppTokens.space1),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class MultiUserOrdersScreen extends ConsumerStatefulWidget {
  const MultiUserOrdersScreen({super.key});

  @override
  ConsumerState<MultiUserOrdersScreen> createState() =>
      _MultiUserOrdersScreenState();
}

class _MultiUserOrdersScreenState extends ConsumerState<MultiUserOrdersScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumePolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumePolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _resumePolling() {
    _pollTimer?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _pollTimer = null;
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final scope = ref.read(connectionScopeStoreProvider).current;
      if (scope == null) return;
      if (_tab == 0) {
        ref.invalidate(scopedPositionsProvider(scope));
      } else {
        ref.invalidate(scopedOrdersProvider(scope));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(
      connectionScopeStoreProvider.select((store) => store.current),
    );
    final connection = ref.watch(
      selectedConnectionProvider.select((store) => store.current),
    );
    final session = ref.watch(userSessionStoreProvider).current;
    final pending = ref.watch(pendingOperationStoreProvider).operations;
    final selectedProvider = scope == null
        ? null
        : _tab == 0
        ? scopedPositionsProvider(scope)
        : scopedOrdersProvider(scope);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lệnh và vị thế'),
        actions: [
          if (scope != null)
            ManualRefreshButton(
              buttonKey: const Key('orders-v2-refresh'),
              onRefresh: () async {
                if (_tab == 0) {
                  ref.invalidate(scopedPositionsProvider(scope));
                } else {
                  ref.invalidate(scopedOrdersProvider(scope));
                }
              },
              isBusy:
                  selectedProvider != null &&
                  (_tab == 0
                      ? ref.watch(scopedPositionsProvider(scope)).isLoading
                      : ref.watch(scopedOrdersProvider(scope)).isLoading),
            ),
        ],
      ),
      body: scope == null
          ? const _NoScopeState()
          : Column(
              children: [
                if (pending.isNotEmpty)
                  _PendingOperationsPanel(operations: pending),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.space2),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Vị thế')),
                      ButtonSegment(value: 1, label: Text('Lệnh')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (selected) {
                      setState(() => _tab = selected.single);
                    },
                  ),
                ),
                Expanded(
                  child: _tab == 0
                      ? ref
                            .watch(scopedPositionsProvider(scope))
                            .when(
                              loading: () => const _LoadingState(
                                label: 'Đang tải vị thế…',
                              ),
                              error: (error, _) => _ErrorState(
                                message: _safeError(error),
                                onRetry: () => ref.invalidate(
                                  scopedPositionsProvider(scope),
                                ),
                              ),
                              data: (result) => _PositionsPage(
                                scope: scope,
                                page: result.page,
                                canTrade:
                                    session?.canTrade == true &&
                                    connection?.canTrade == true,
                              ),
                            )
                      : ref
                            .watch(scopedOrdersProvider(scope))
                            .when(
                              loading: () =>
                                  const _LoadingState(label: 'Đang tải lệnh…'),
                              error: (error, _) => _ErrorState(
                                message: _safeError(error),
                                onRetry: () =>
                                    ref.invalidate(scopedOrdersProvider(scope)),
                              ),
                              data: (result) => _OrdersPage(
                                scope: scope,
                                page: result.page,
                                canTrade:
                                    session?.canTrade == true &&
                                    connection?.canTrade == true,
                              ),
                            ),
                ),
              ],
            ),
    );
  }
}

class _PositionsPage extends StatelessWidget {
  const _PositionsPage({
    required this.scope,
    required this.page,
    required this.canTrade,
  });
  final ConnectionScope scope;
  final NormalizedPage<NormalizedPosition> page;
  final bool canTrade;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _DataQualityBanner(meta: page.meta),
      if (page.rows.isNotEmpty)
        _CloseAllPositionsAction(scope: scope, page: page, canTrade: canTrade),
      if (page.rows.isEmpty)
        const Expanded(
          child: _CenteredNotice(
            icon: Icons.stacked_line_chart,
            text: 'Không có vị thế đang mở.',
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            key: const Key('normalized-position-list'),
            itemCount: page.rows.length,
            itemBuilder: (context, index) {
              final row = page.rows[index];
              final target = _closeIdentity(row);
              final allowed =
                  canTrade &&
                  page.meta.usableForActions &&
                  scope.exchange == 'OKX' &&
                  target != null;
              return Card(
                margin: const EdgeInsets.fromLTRB(
                  AppTokens.space4,
                  AppTokens.space1,
                  AppTokens.space4,
                  AppTokens.space1,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.space3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.instrument.isEmpty ? 'Vị thế' : row.instrument,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppTokens.space1),
                      Text(
                        '${row.side ?? '—'} · ${_nativeQuantity(row.nativeQuantity, row.quantityUnit, row.nativeAsset)}',
                      ),
                      if (row.contractValue != null || row.contractType != null)
                        Text(
                          'Hợp đồng ${row.contractValue ?? '—'} ${row.contractValueUnit ?? ''} · ${row.contractType ?? '—'} · Thanh toán ${row.settlementAsset ?? '—'}',
                        ),
                      Text(
                        'Giá vào ${row.entryPrice ?? '—'} · Đánh dấu ${row.markPrice ?? '—'} · Lãi/lỗ ${row.unrealizedPnl ?? '—'}',
                      ),
                      if (target == null)
                        const Padding(
                          padding: EdgeInsets.only(top: AppTokens.space1),
                          child: Text('Thiếu định danh gốc; thao tác bị khóa.'),
                        )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: Key('close-position-${row.instrument}-$index'),
                            onPressed: allowed
                                ? () => _prepareAndConfirm(
                                    context,
                                    scope,
                                    page.meta,
                                    'close_position',
                                    target,
                                    'Đóng vị thế',
                                    capturedDetails: {
                                      'Sàn': scope.exchange,
                                      'Sản phẩm': scope.product,
                                      'Môi trường': scope.environment,
                                      'Khu vực': scope.region,
                                      'Mã thị trường': row.instrument,
                                      'Chiều': row.side ?? 'Chưa rõ',
                                      'Số lượng gốc': _nativeQuantity(
                                        row.nativeQuantity,
                                        row.quantityUnit,
                                        row.nativeAsset,
                                      ),
                                      'Hậu quả':
                                          'Gửi yêu cầu đóng toàn bộ vị thế đã chọn theo giá thị trường.',
                                    },
                                  )
                                : null,
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Đóng vị thế'),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}

class _OrdersPage extends StatelessWidget {
  const _OrdersPage({
    required this.scope,
    required this.page,
    required this.canTrade,
  });
  final ConnectionScope scope;
  final NormalizedPage<NormalizedOrder> page;
  final bool canTrade;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _DataQualityBanner(meta: page.meta),
      if (scope.exchange == 'BINANCE')
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppTokens.space4),
          child: _InfoText(
            text:
                'Thao tác Binance bị khóa trong ứng dụng này; trạng thái demo không bật lệnh production.',
          ),
        ),
      if (page.rows.isEmpty)
        const Expanded(
          child: _CenteredNotice(
            icon: Icons.receipt_long_outlined,
            text: 'Máy chủ chưa trả về lệnh cho sản phẩm này.',
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            key: const Key('normalized-order-list'),
            itemCount: page.rows.length,
            itemBuilder: (context, index) {
              final row = page.rows[index];
              final target = _cancelIdentity(row, scope);
              final allowed =
                  canTrade &&
                  page.meta.usableForActions &&
                  scope.exchange == 'OKX' &&
                  target != null &&
                  const {
                    'LIVE',
                    'PARTIALLY_FILLED',
                  }.contains(row.status.toUpperCase());
              return Card(
                margin: const EdgeInsets.fromLTRB(
                  AppTokens.space4,
                  AppTokens.space1,
                  AppTokens.space4,
                  AppTokens.space1,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.space3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.instrument.isEmpty ? 'Lệnh' : row.instrument} · ${row.side ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Mã ${row.orderId.isEmpty ? '—' : row.orderId} · ${row.orderType ?? '—'} · ${row.status}',
                      ),
                      Text(
                        'Số lượng gốc ${_nativeQuantity(row.nativeQuantity, row.quantityUnit, row.nativeAsset)} · Đã khớp ${_nativeQuantity(row.filledQuantity, row.filledQuantityUnit, null)} · Giá giới hạn ${row.limitPrice ?? '—'} · Giá khớp ${row.averagePrice ?? '—'}',
                      ),
                      if (scope.exchange == 'OKX')
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: Key('cancel-order-${row.orderId}-$index'),
                            onPressed: allowed
                                ? () => _prepareAndConfirm(
                                    context,
                                    scope,
                                    page.meta,
                                    'cancel_order',
                                    target!,
                                    'Hủy lệnh limit',
                                    capturedDetails: {
                                      'Sàn': scope.exchange,
                                      'Sản phẩm': scope.product,
                                      'Môi trường': scope.environment,
                                      'Khu vực': scope.region,
                                      'Mã thị trường': row.instrument,
                                      'Chiều': row.side ?? 'Chưa rõ',
                                      'Số lượng gốc': _nativeQuantity(
                                        row.nativeQuantity,
                                        row.quantityUnit,
                                        row.nativeAsset,
                                      ),
                                      'Đã khớp': _nativeQuantity(
                                        row.filledQuantity,
                                        row.filledQuantityUnit,
                                        row.nativeAsset,
                                      ),
                                      'Giá limit': row.limitPrice ?? 'Chưa rõ',
                                      'Hậu quả':
                                          'Hủy phần còn lại của lệnh. Khớp mới vẫn có thể xảy ra trong lúc xử lý.',
                                    },
                                  )
                                : null,
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Hủy lệnh'),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}

class _CloseAllPositionsAction extends StatelessWidget {
  const _CloseAllPositionsAction({
    required this.scope,
    required this.page,
    required this.canTrade,
  });

  final ConnectionScope scope;
  final NormalizedPage<NormalizedPosition> page;
  final bool canTrade;

  @override
  Widget build(BuildContext context) {
    final supported = page.rows
        .where((row) => _closeIdentity(row) != null)
        .length;
    final unsupported = page.rows.length - supported;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space3,
        AppTokens.space1,
        AppTokens.space3,
        AppTokens.space1,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Hỗ trợ đóng: $supported · Giữ nguyên: $unsupported',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
          ),
          FilledButton.tonalIcon(
            key: const Key('close-all-supported-positions'),
            onPressed: canTrade && page.meta.usableForActions && supported > 0
                ? () => _closeSupportedPositions(context, scope, page)
                : null,
            icon: const Icon(Icons.close_fullscreen_rounded),
            label: const Text('Đóng tất cả'),
          ),
        ],
      ),
    );
  }
}

Future<void> _closeSupportedPositions(
  BuildContext context,
  ConnectionScope scope,
  NormalizedPage<NormalizedPosition> page,
) async {
  final supported = page.rows
      .where((row) => _closeIdentity(row) != null)
      .toList(growable: false);
  final unsupported = page.rows
      .where((row) => _closeIdentity(row) == null)
      .toList(growable: false);
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: const Text('Đóng tất cả vị thế được hỗ trợ'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Các vị thế được liệt kê sẽ được chuẩn bị và xác nhận riêng từng vị thế. Những vị thế không hỗ trợ hoặc thiếu định danh sẽ không bị thay đổi.',
            ),
            const SizedBox(height: AppTokens.space2),
            const Text(
              'Sẽ chuẩn bị',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final row in supported)
              Text(
                '${row.instrument} · ${row.side ?? 'chưa rõ'} · ${_nativeQuantity(row.nativeQuantity, row.quantityUnit, row.nativeAsset)}',
              ),
            if (unsupported.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space2),
              const Text(
                'Giữ nguyên',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final row in unsupported)
                Text(
                  '${row.instrument.isEmpty ? 'Vị thế chưa rõ' : row.instrument} · ${row.product} · ${row.side ?? 'chiều chưa rõ'} · không đủ định danh cho thao tác',
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('close-all-review-each'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Xem lại từng vị thế'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;
  for (final row in supported) {
    final target = _closeIdentity(row);
    if (target == null) continue;
    final completed = await _prepareAndConfirm(
      context,
      scope,
      page.meta,
      'close_position',
      target,
      'Đóng vị thế ${row.instrument}',
      capturedDetails: {
        'Sàn': scope.exchange,
        'Sản phẩm': scope.product,
        'Môi trường': scope.environment,
        'Khu vực': scope.region,
        'Mã thị trường': row.instrument,
        'Chiều': row.side ?? 'Chưa rõ',
        'Số lượng gốc': _nativeQuantity(
          row.nativeQuantity,
          row.quantityUnit,
          row.nativeAsset,
        ),
        'Hậu quả': 'Gửi yêu cầu đóng toàn bộ vị thế này theo giá thị trường.',
      },
    );
    if (!completed || !context.mounted) {
      if (context.mounted) {
        _showNotice(
          context,
          'Chuỗi dừng lại. Hãy làm mới dữ liệu và tra cứu mọi thao tác đang xử lý trước khi tiếp tục.',
        );
      }
      return;
    }
  }
}

class MultiUserStrategyScreen extends ConsumerWidget {
  const MultiUserStrategyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(
      connectionScopeStoreProvider.select((store) => store.current),
    );
    final session = ref.watch(userSessionStoreProvider).current;
    final connection = ref.watch(
      selectedConnectionProvider.select((store) => store.current),
    );
    if (scope == null || session == null || !session.canReadPrivate) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chiến thuật')),
        body: const _NoScopeState(),
      );
    }
    if (scope.exchange != 'OKX' || scope.product != 'SWAP') {
      return Scaffold(
        appBar: AppBar(title: Text('Chiến thuật')),
        body: const _UnavailableState(
          message:
              'Chiến thuật yêu cầu kết nối OKX và sản phẩm SWAP USDT tuyến tính. Dữ liệu kết nối hiện tại vẫn được giữ nguyên.',
        ),
      );
    }
    if (connection?.connectionId != scope.connectionId) {
      return const _NoScopeState();
    }
    final api = ref.read(multiUserApiClientProvider);
    final generation = ref.read(userSessionStoreProvider).generation;
    return ProviderScope(
      overrides: [
        strategyApiProvider.overrideWithValue(
          OwnedStrategyApi(client: api, scope: scope),
        ),
      ],
      child: StrategyScreen(
        key: ValueKey('${scope.connectionId}:${scope.product}:$generation'),
        ownedSession: session,
        ownedScope: scope,
        ownedGeneration: generation,
      ),
    );
  }
}

/// Keeps OKX-only public panels tied to the selected venue and market context.
/// A Binance selection gets an explicit unavailable state instead of OKX data.
class MultiUserPublicPanelBoundary extends ConsumerWidget {
  const MultiUserPublicPanelBoundary({
    super.key,
    required this.feed,
    required this.supportedProducts,
    required this.child,
  });

  final String feed;
  final Set<String> supportedProducts;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(
      connectionScopeStoreProvider.select((store) => store.current),
    );
    if (scope != null &&
        (scope.exchange != 'OKX' ||
            !supportedProducts.contains(scope.product))) {
      return Scaffold(
        appBar: AppBar(title: Text(feed)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space4),
            child: Text(
              scope.exchange == 'BINANCE'
                  ? 'Nguồn công khai $feed hiện chỉ được xác minh cho OKX. Dữ liệu Binance ${scope.environment} ${scope.product} chưa khả dụng; không hiển thị báo giá OKX dưới kết nối Binance.'
                  : '$feed chỉ hỗ trợ OKX ${supportedProducts.join(' / ')}. Kết nối hiện tại là ${scope.product}.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final contextKey = scope == null
        ? 'OKX:public:$feed'
        : '${scope.exchange}:${scope.product}:${scope.environment}:${scope.region}:$feed:${scope.generation}';
    return KeyedSubtree(key: ValueKey(contextKey), child: child);
  }
}

class MultiUserConnectionContextStrip extends ConsumerStatefulWidget {
  const MultiUserConnectionContextStrip({super.key});

  @override
  ConsumerState<MultiUserConnectionContextStrip> createState() =>
      _MultiUserConnectionContextStripState();
}

class _MultiUserConnectionContextStripState
    extends ConsumerState<MultiUserConnectionContextStrip> {
  Timer? _authorityExpiryTimer;
  String? _scheduledIdentity;
  bool _stepUpBusy = false;
  String? _stepUpMessage;

  @override
  void dispose() {
    _authorityExpiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleAuthorityExpiry(UserSession? session) {
    final identity = session == null
        ? null
        : '${session.userId}:${session.sessionId}:${session.stepUpUntil?.microsecondsSinceEpoch}:${session.expiresAt.microsecondsSinceEpoch}';
    if (identity == _scheduledIdentity) return;
    _scheduledIdentity = identity;
    _authorityExpiryTimer?.cancel();
    if (session == null) return;
    final expiries = [
      session.expiresAt,
      if (session.stepUpUntil != null) session.stepUpUntil!,
    ];
    final next = expiries
        .where((value) => value.isAfter(DateTime.now()))
        .fold<DateTime?>(null, (earliest, value) {
          if (earliest == null || value.isBefore(earliest)) return value;
          return earliest;
        });
    if (next == null) return;
    _authorityExpiryTimer = Timer(next.difference(DateTime.now()), () {
      if (!mounted) return;
      setState(() => _scheduledIdentity = null);
    });
  }

  void _openConnectionSelector() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ConnectionsPage()),
    );
  }

  Future<void> _requestTradeStepUp(UserSession owner) async {
    if (_stepUpBusy) return;
    final sessions = ref.read(userSessionStoreProvider);
    if (!sessions.hasSameOwner(owner) || !owner.canReadPrivate) return;
    setState(() {
      _stepUpBusy = true;
      _stepUpMessage = null;
    });
    try {
      final credentials = await showConnectionStepUpDialog(
        context,
        owner: owner,
      );
      if (!mounted || credentials == null || !sessions.hasSameOwner(owner)) {
        return;
      }
      await ref
          .read(multiUserControllerProvider)
          .stepUp(password: credentials.password, totp: credentials.totp);
      if (!mounted || !sessions.hasSameOwner(owner)) return;
      setState(() {
        _stepUpMessage = sessions.current?.canTrade == true
            ? 'Xác minh TOTP gần đây đã bật.'
            : 'Chưa thể bật quyền giao dịch.';
      });
    } catch (_) {
      if (mounted && sessions.hasSameOwner(owner)) {
        final safe = ref.read(multiUserControllerProvider).errorMessage;
        setState(() => _stepUpMessage = safe ?? 'Không thể xác minh lại.');
      }
    } finally {
      if (mounted) setState(() => _stepUpBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionStoreProvider).current;
    _scheduleAuthorityExpiry(session);
    if (session?.canReadPrivate != true) return const SizedBox.shrink();
    final scope = ref.watch(
      connectionScopeStoreProvider.select((store) => store.current),
    );
    final connection = ref.watch(
      selectedConnectionProvider.select((store) => store.current),
    );
    final palette = AppPalette.of(context);
    final selected =
        scope != null &&
        connection?.connectionId == scope.connectionId &&
        scope.belongsTo(session!) &&
        scope.exchange == connection?.exchange &&
        scope.environment == connection?.environment &&
        scope.region == connection?.region;
    final identity = selected
        ? '${connection!.displayName} · ${scope.exchange} ${scope.product} · ${scope.environment} ${scope.region}'
        : 'Chưa chọn kết nối';
    final hasReadCapability =
        selected && connection!.capabilities.contains('read');
    final connectionState = !selected
        ? 'Chọn một kết nối đã xác minh để xem dữ liệu riêng tư.'
        : !hasReadCapability
        ? 'Kết nối này chưa cấp quyền đọc riêng tư.'
        : connection!.status == 'RECONCILING'
        ? 'Đang đồng bộ kết nối · quyền đọc riêng tư đã được cấp.'
        : 'Kết nối đã xác minh · quyền đọc riêng tư đã được cấp.';
    final tradeState =
        selected &&
            hasReadCapability &&
            session?.canTrade == true &&
            connection?.canTrade == true
        ? 'Giao dịch đã xác minh gần đây.'
        : 'Chỉ đọc · cần xác minh TOTP để giao dịch.';
    return Material(
      color: palette.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space3,
          vertical: AppTokens.space2,
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: AppTokens.space1,
          spacing: AppTokens.space2,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    identity,
                    key: const Key('selected-connection-context'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    connectionState,
                    key: const Key('selected-connection-permission-state'),
                    softWrap: true,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  Text(
                    tradeState,
                    key: const Key('selected-connection-trade-state'),
                    softWrap: true,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  if (selected &&
                      hasReadCapability &&
                      connection!.canTrade &&
                      session?.canTrade != true)
                    OutlinedButton.icon(
                      key: const Key('verify-trade-step-up'),
                      onPressed: _stepUpBusy
                          ? null
                          : () => _requestTradeStepUp(session!),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(
                          48,
                          AppTokens.minimumTouchTarget,
                        ),
                      ),
                      icon: _stepUpBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user_outlined),
                      label: const Text('Xác minh TOTP'),
                    ),
                  if (_stepUpMessage != null)
                    Text(
                      _stepUpMessage!,
                      key: const Key('trade-step-up-status'),
                      softWrap: true,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: const Key('change-connection-context'),
              onPressed: _openConnectionSelector,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, AppTokens.minimumTouchTarget),
              ),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Đổi kết nối'),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, String>? _closeIdentity(NormalizedPosition row) {
  final product = row.product.toUpperCase();
  final mode = row.marginMode?.toLowerCase();
  final side = row.side?.toLowerCase();
  final positionUnitsAreUsable = product == 'MARGIN'
      ? row.quantityUnit == 'base' &&
            _validNonzeroWireDecimal(row.nativeQuantity) &&
            row.nativeAsset != null &&
            row.nativeAsset!.isNotEmpty
      : row.quantityUnit == 'contracts' &&
            row.nativeQuantity != null &&
            _validNonzeroWireDecimal(row.nativeQuantity) &&
            _positiveWireDecimal(row.contractValue) &&
            row.contractValueUnit != null &&
            row.contractValueUnit!.isNotEmpty &&
            const {'linear', 'inverse'}.contains(row.contractType) &&
            row.settlementAsset != null &&
            row.settlementAsset!.isNotEmpty &&
            row.metadataVersion != null &&
            row.metadataVersion!.isNotEmpty;
  if (row.instrument.isEmpty ||
      !{'MARGIN', 'SWAP', 'FUTURES'}.contains(product) ||
      !{'cross', 'isolated'}.contains(mode) ||
      !{'net', 'long', 'short'}.contains(side) ||
      !positionUnitsAreUsable ||
      (row.positionId != null &&
          (row.positionId!.isEmpty || row.positionId!.length > 128)) ||
      (product == 'MARGIN'
          ? row.marginCurrency == null ||
                !RegExp(r'^[A-Z0-9]{2,16}$').hasMatch(row.marginCurrency!)
          : false)) {
    return null;
  }
  return {
    'instrumentType': product,
    'instrumentId': row.instrument,
    'positionSide': side!,
    'marginMode': mode!,
    if (row.positionId != null) 'positionId': row.positionId!,
    if (product == 'MARGIN') 'marginCurrency': row.marginCurrency!,
  };
}

Map<String, String>? _cancelIdentity(
  NormalizedOrder row,
  ConnectionScope scope,
) {
  final price = row.limitPrice;
  final quantity = row.nativeQuantity;
  final side = row.side?.toLowerCase();
  final contractProduct = const {
    'SWAP',
    'FUTURES',
  }.contains(scope.product.toUpperCase());
  final orderUnitsAreUsable = contractProduct
      ? row.quantityUnit == 'contracts' &&
            row.nativeAsset != null &&
            row.nativeAsset!.isNotEmpty &&
            row.filledQuantityUnit == 'contracts'
      : row.quantityUnit == 'base' &&
            row.nativeAsset != null &&
            row.nativeAsset!.isNotEmpty &&
            row.filledQuantityUnit == 'base';
  if (scope.exchange != 'OKX' ||
      !{'SPOT', 'MARGIN', 'SWAP', 'FUTURES'}.contains(scope.product) ||
      row.orderId.isEmpty ||
      row.orderId.length > 128 ||
      row.instrument.isEmpty ||
      row.orderType?.toLowerCase() != 'limit' ||
      !const {'LIVE', 'PARTIALLY_FILLED'}.contains(row.status.toUpperCase()) ||
      !orderUnitsAreUsable ||
      !{'buy', 'sell'}.contains(side) ||
      !_positiveWireDecimal(price) ||
      !_positiveWireDecimal(quantity)) {
    return null;
  }
  return {
    'instType': scope.product,
    'instId': row.instrument,
    'ordId': row.orderId,
    'ordType': 'limit',
    'side': side!,
    'px': price!,
    'sz': quantity!,
  };
}

bool _positiveWireDecimal(String? value) {
  if (value == null ||
      value.length > 512 ||
      !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) {
    return false;
  }
  final parsed = double.tryParse(value);
  return parsed != null && parsed.isFinite && parsed > 0;
}

bool _validNonzeroWireDecimal(String? value) {
  if (value == null ||
      value.length > 512 ||
      !RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value)) {
    return false;
  }
  final parsed = double.tryParse(value);
  return parsed != null && parsed.isFinite && parsed != 0;
}

Future<bool> _prepareAndConfirm(
  BuildContext context,
  ConnectionScope capturedScope,
  DataMeta dataMeta,
  String action,
  Map<String, String> target,
  String label, {
  required Map<String, String> capturedDetails,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final scopes = container.read(connectionScopeStoreProvider);
  final sessions = container.read(userSessionStoreProvider);
  final connection = container.read(selectedConnectionProvider).current;
  final session = sessions.current;
  final sessionGeneration = sessions.generation;
  if (!scopes.matches(capturedScope.generation, capturedScope) ||
      session == null ||
      !session.canTrade ||
      connection == null ||
      !connection.canTrade ||
      connection.connectionId != capturedScope.connectionId ||
      capturedScope.exchange != 'OKX' ||
      !dataMeta.usableForActions) {
    _showNotice(context, 'Phiên hoặc quyền kết nối đã thay đổi. Hãy tải lại.');
    return false;
  }

  final api = container.read(multiUserApiClientProvider);
  final pendingStore = container.read(pendingOperationStoreProvider);
  final connectionLabel = connection.displayName;
  Map<String, dynamic> prepared;
  try {
    prepared = await api.prepareAction(
      capturedScope,
      action: action,
      targetIdentity: target,
    );
  } catch (error) {
    if (context.mounted && sessions.matches(sessionGeneration, session)) {
      _showNotice(context, _safeError(error));
    }
    return false;
  }
  if (!context.mounted ||
      !sessions.matches(sessionGeneration, session) ||
      !scopes.matches(capturedScope.generation, capturedScope) ||
      !dataMeta.usableForActions) {
    if (context.mounted && sessions.matches(sessionGeneration, session)) {
      _showNotice(
        context,
        'Dữ liệu hoặc quyền xác nhận đã hết hạn. Hãy tải lại.',
      );
    }
    return false;
  }
  final operationId = prepared['operationId'] as String;
  final confirmationToken = prepared['confirmationToken'] as String;
  final expiry = DateTime.parse(prepared['expiresAt'] as String).toUtc();
  if (!expiry.isAfter(DateTime.now().toUtc())) {
    _showNotice(context, 'Yêu cầu xác nhận đã hết hạn. Hãy tạo lại.');
    return false;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ScopedActionConfirmation(
      scope: capturedScope,
      ownerSession: session,
      dataMeta: dataMeta,
      expiry: expiry,
      title: label,
      capturedDetails: {'Kết nối': connection.displayName, ...capturedDetails},
      preparedSummary: _preparedSummary(prepared),
    ),
  );
  if (confirmed != true) return false;

  final latestSession = sessions.current;
  if (!sessions.matches(sessionGeneration, session) ||
      !scopes.matches(capturedScope.generation, capturedScope) ||
      latestSession == null ||
      !latestSession.canTrade ||
      !expiry.isAfter(DateTime.now().toUtc()) ||
      container.read(selectedConnectionProvider).current?.canTrade != true) {
    _showNotice(
      context,
      'Phiên, quyền hoặc xác nhận đã hết hạn. Hãy chuẩn bị lại.',
    );
    return false;
  }

  final idempotencyKey = _newIdempotencyKey();
  try {
    final result = await api.executeAction(
      capturedScope,
      action: action,
      operationId: operationId,
      confirmationToken: confirmationToken,
      idempotencyKey: idempotencyKey,
    );
    if (!sessions.hasSameOwner(session)) {
      return false;
    }
    _refreshAfterPrivateAction(container, capturedScope);
    if (_operationNeedsFollowup(result['status'])) {
      pendingStore.add(
        PendingOperation(
          scope: capturedScope,
          operationId: operationId,
          action: action,
          createdAt: DateTime.now().toUtc(),
          connectionLabel: connectionLabel,
          status: _statusOf(result),
          targets: _targetProofs(result),
        ),
      );
    }
    if (context.mounted) _showOperationStatus(context, result);
    return const {'SUCCEEDED', 'COMPLETED'}.contains(_statusOf(result));
  } catch (_) {
    if (!sessions.hasSameOwner(session)) return false;
    try {
      final result = await api.operationResult(
        capturedScope,
        operationId,
        action,
      );
      if (!sessions.hasSameOwner(session)) {
        return false;
      }
      _refreshAfterPrivateAction(container, capturedScope);
      if (_operationNeedsFollowup(result['status'])) {
        pendingStore.add(
          PendingOperation(
            scope: capturedScope,
            operationId: operationId,
            action: action,
            createdAt: DateTime.now().toUtc(),
            connectionLabel: connectionLabel,
            status: _statusOf(result),
            targets: _targetProofs(result),
          ),
        );
      }
      if (context.mounted) _showOperationStatus(context, result);
      return const {'SUCCEEDED', 'COMPLETED'}.contains(_statusOf(result));
    } catch (_) {
      if (!sessions.hasSameOwner(session)) return false;
      pendingStore.add(
        PendingOperation(
          scope: capturedScope,
          operationId: operationId,
          action: action,
          createdAt: DateTime.now().toUtc(),
          connectionLabel: connectionLabel,
        ),
      );
      _refreshAfterPrivateAction(container, capturedScope);
      if (context.mounted) {
        _showNotice(
          context,
          'UNKNOWN · Máy chủ chưa xác nhận kết quả. Không gửi lại thao tác này.',
        );
      }
      return false;
    }
  }
  return false;
}

String _statusOf(Map<String, dynamic> result) => result['status'] is String
    ? (result['status'] as String).toUpperCase()
    : 'UNKNOWN';

void _refreshAfterPrivateAction(
  ProviderContainer container,
  ConnectionScope scope,
) {
  container.invalidate(scopedPositionsProvider(scope));
  container.invalidate(scopedOrdersProvider(scope));
  container.invalidate(scopedBalancesProvider(scope));
}

bool _operationNeedsFollowup(Object? status) => !const {
  'SUCCEEDED',
  'COMPLETED',
  'FAILED',
  'CANCELED',
  'EXPIRED',
}.contains(status is String ? status.toUpperCase() : 'UNKNOWN');

class _ScopedActionConfirmation extends ConsumerStatefulWidget {
  const _ScopedActionConfirmation({
    required this.scope,
    required this.ownerSession,
    required this.dataMeta,
    required this.expiry,
    required this.title,
    required this.capturedDetails,
    required this.preparedSummary,
  });

  final ConnectionScope scope;
  final UserSession ownerSession;
  final DataMeta dataMeta;
  final DateTime expiry;
  final String title;
  final Map<String, String> capturedDetails;
  final Map<String, String> preparedSummary;

  @override
  ConsumerState<_ScopedActionConfirmation> createState() =>
      _ScopedActionConfirmationState();
}

class _ScopedActionConfirmationState
    extends ConsumerState<_ScopedActionConfirmation> {
  Timer? _expiryTicker;
  bool _closingForAuthorityChange = false;

  void _closeForAuthorityChange() {
    if (!mounted || _closingForAuthorityChange) return;
    _closingForAuthorityChange = true;
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || route?.isCurrent != true) return;
      Navigator.of(context).pop(false);
    });
  }

  @override
  void initState() {
    super.initState();
    _expiryTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedScope = ref.watch(
      connectionScopeStoreProvider.select((store) => store.current),
    );
    final session = ref.watch(userSessionStoreProvider).current;
    final connection = ref.watch(
      selectedConnectionProvider.select((store) => store.current),
    );
    final current =
        selectedScope?.sameAuthority(widget.scope) == true &&
        session?.sameIdentity(widget.ownerSession) == true &&
        session?.canTrade == true &&
        connection?.connectionId == widget.scope.connectionId &&
        connection?.canTrade == true &&
        widget.dataMeta.usableForActions &&
        widget.expiry.isAfter(DateTime.now().toUtc());
    ref.listen<ConnectionScope?>(
      connectionScopeStoreProvider.select((store) => store.current),
      (previous, next) {
        if (next?.sameAuthority(widget.scope) != true) {
          _closeForAuthorityChange();
        }
      },
    );
    ref.listen<UserSession?>(
      userSessionStoreProvider.select((store) => store.current),
      (previous, next) {
        if (next?.sameIdentity(widget.ownerSession) != true) {
          _closeForAuthorityChange();
        }
      },
    );
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Đối chiếu thông tin đã chọn với xác nhận mới từ máy chủ. Giá thị trường có thể thay đổi.',
            ),
            const SizedBox(height: AppTokens.space3),
            const Text(
              'Thông tin đã chọn',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final entry in widget.capturedDetails.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.space1),
                child: Text('${entry.key}: ${entry.value}'),
              ),
            const SizedBox(height: AppTokens.space2),
            const Text(
              'Ảnh chụp được máy chủ chuẩn bị',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final entry in widget.preparedSummary.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.space1),
                child: Text('${entry.key}: ${entry.value}'),
              ),
            const SizedBox(height: AppTokens.space2),
            Text('Hết hạn: ${widget.expiry.toLocal()}'),
            if (!current)
              const Padding(
                padding: EdgeInsets.only(top: AppTokens.space2),
                child: Text(
                  'Phiên, quyền, tài khoản hoặc xác nhận đã hết hạn. Đóng hộp thoại này.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('prepared-action-confirm'),
          onPressed: current ? () => Navigator.pop(context, true) : null,
          child: const Text('Xác nhận một lần'),
        ),
      ],
    );
  }
}

class _PendingOperationsPanel extends ConsumerWidget {
  const _PendingOperationsPanel({required this.operations});
  final List<PendingOperation> operations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionStoreProvider).current;
    return Card(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.space3,
        AppTokens.space2,
        AppTokens.space3,
        AppTokens.space1,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cần tra cứu thao tác',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppTokens.space1),
            for (final operation in operations) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${operation.connectionLabel} · ${operation.scope.product}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${operation.action} · ${operation.status}'),
                trailing: TextButton(
                  onPressed:
                      session?.userId == operation.scope.userId &&
                          session?.canReadPrivate == true
                      ? () async {
                          final owner = session!;
                          final generation = ref
                              .read(userSessionStoreProvider)
                              .generation;
                          final store = ref.read(pendingOperationStoreProvider);
                          try {
                            final result = await ref
                                .read(multiUserApiClientProvider)
                                .operationResult(
                                  operation.scope,
                                  operation.operationId,
                                  operation.action,
                                );
                            if (!ref
                                .read(userSessionStoreProvider)
                                .matches(generation, owner))
                              return;
                            final status = _statusOf(result);
                            if (_operationNeedsFollowup(status)) {
                              store.updateProof(
                                operation,
                                status,
                                _targetProofs(result),
                              );
                            } else {
                              store.remove(operation);
                            }
                          } catch (_) {
                            if (ref
                                .read(userSessionStoreProvider)
                                .matches(generation, owner)) {
                              store.update(operation, 'UNKNOWN');
                            }
                          }
                        }
                      : null,
                  child: const Text('Tra cứu'),
                ),
              ),
              for (final target in operation.targets)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppTokens.space3,
                    bottom: AppTokens.space1,
                  ),
                  child: Text(_targetProofLabel(target)),
                ),
              const Divider(height: AppTokens.space3),
            ],
            const Text(
              'Mỗi yêu cầu vẫn gắn với tài khoản và sản phẩm ban đầu. Ứng dụng không gửi lại thao tác.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String _newIdempotencyKey() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String _nativeQuantity(String? quantity, String? unit, String? asset) {
  if (quantity == null) return 'Chưa rõ';
  final denomination = unit ?? asset;
  return denomination == null || denomination.isEmpty
      ? '$quantity · đơn vị chưa rõ'
      : '$quantity $denomination';
}

Map<String, String> _preparedSummary(Map<String, dynamic> operation) {
  final summary = connectionJsonMap(operation['summary']);
  final result = <String, String>{};
  final identity = connectionJsonMap(summary['identity']);
  for (final pair in <(String, String)>[
    ('direction', 'Chiều đã xác minh'),
    ('currentSize', 'Số lượng vị thế hiện tại'),
    ('price', 'Giá limit'),
    ('originalSize', 'Kích thước gốc'),
    ('filledSize', 'Đã khớp'),
    ('remainingSize', 'Còn lại'),
  ]) {
    final value = summary[pair.$1];
    if (value is String) result[pair.$2] = value;
  }
  for (final entry in identity.entries) {
    if (entry.value is String) {
      result['Định danh ${entry.key}'] = entry.value as String;
    }
  }
  return result;
}

List<Map<String, dynamic>> _targetProofs(Map<String, dynamic> operation) {
  final rawTargets = operation['targets'];
  if (rawTargets is! List) return const [];
  return List.unmodifiable(
    rawTargets.map((raw) {
      final target = connectionJsonMap(raw);
      final result = connectionJsonMap(target['result']);
      const resultKeys = {
        'reason',
        'orderState',
        'filledSize',
        'remainingSize',
        'currentSize',
        'positionVerified',
        'category',
        'completedTargets',
        'targetCount',
      };
      return <String, dynamic>{
        'index': target['index'],
        'status': target['status'] is String
            ? (target['status'] as String).toUpperCase()
            : 'UNKNOWN',
        'result': {
          for (final key in resultKeys)
            if (result[key] is String ||
                result[key] is bool ||
                result[key] is int)
              key: result[key],
        },
      };
    }),
  );
}

String _targetProofLabel(Map<String, dynamic> target) {
  final result = connectionJsonMap(target['result']);
  final details = result.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(' · ');
  final index = target['index'] is int ? (target['index'] as int) + 1 : '—';
  final status = target['status'] is String ? target['status'] : 'UNKNOWN';
  return details.isEmpty
      ? 'Mục tiêu $index · $status'
      : 'Mục tiêu $index · $status · $details';
}

void _showOperationStatus(BuildContext context, Map<String, dynamic> result) {
  final status = result['status'];
  final normalized = status is String ? status.toUpperCase() : 'UNKNOWN';
  final message = switch (normalized) {
    'SUCCEEDED' || 'COMPLETED' => 'Máy chủ xác nhận: $normalized.',
    'FAILED' || 'CANCELED' || 'EXPIRED' => 'Máy chủ báo: $normalized.',
    _ => '$normalized · Kết quả chưa được xác nhận hoàn tất.',
  };
  _showNotice(context, message);
}

void _showNotice(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _DataQualityBanner extends StatelessWidget {
  const _DataQualityBanner({required this.meta});
  final DataMeta meta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = meta.stale
        ? 'Dữ liệu đã cũ; thao tác bị khóa.'
        : !meta.complete
        ? 'Dữ liệu chưa đầy đủ; tổng quan và thao tác bị hạn chế.'
        : meta.usableForActions
        ? 'Dữ liệu mới đến ${meta.asOf?.toLocal() ?? '—'}.'
        : 'Bằng chứng mới của ảnh chụp dữ liệu đã hết hạn.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.space3),
      color: palette.surface,
      child: Semantics(liveRegion: true, child: Text(text)),
    );
  }
}

class _NoScopeState extends StatelessWidget {
  const _NoScopeState();

  @override
  Widget build(BuildContext context) => _CenteredNotice(
    icon: Icons.link_rounded,
    text:
        'Chọn một kết nối sàn và sản phẩm trong Cài đặt để xem dữ liệu riêng tư.',
    action: OutlinedButton.icon(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ConnectionsPage())),
      icon: const Icon(Icons.manage_accounts_outlined),
      label: const Text('Mở kết nối'),
    ),
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppTokens.space3),
        Text(label),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CenteredNotice(
    icon: Icons.cloud_off_outlined,
    text: message,
    action: TextButton(onPressed: onRetry, child: const Text('Thử lại')),
  );
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _CenteredNotice(
    icon: Icons.info_outline_rounded,
    text: message,
    action: onRetry == null
        ? null
        : TextButton(onPressed: onRetry, child: const Text('Thử lại')),
  );
}

class _CenteredNotice extends StatelessWidget {
  const _CenteredNotice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: palette.muted),
              const SizedBox(height: AppTokens.space3),
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: AppTokens.space2),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
  );
}

String _safeError(Object error) {
  if (error is BackendDataException) return error.message;
  return 'Không thể tải dữ liệu từ máy chủ. Hãy thử lại.';
}
