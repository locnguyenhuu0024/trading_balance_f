import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/okx_position_model.dart';
import '../../data/trade_api_client.dart';
import '../providers/trade_session_provider.dart';
import 'position_action_controls.dart';

/// Loads authoritative backend targets only while this user-opened dialog is
/// visible. Native OKX display positions are never promoted to action targets.
class BackendPositionActionsDialog extends ConsumerWidget {
  const BackendPositionActionsDialog({
    super.key,
    required this.expectedSession,
    required this.expectedGeneration,
  });

  final TradeSession? expectedSession;
  final int expectedGeneration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final sessionState = ref.watch(tradeSessionProvider);
    final backendSession = ref.watch(backendDataSessionProvider);
    final session = expectedSession;
    final sessionMatches =
        session != null &&
        sessionState.isAuthenticated &&
        _sameSession(sessionState.session, session) &&
        backendSession.matches(expectedGeneration, session);

    final content = session == null
        ? const _ActionTargetsMessage(
            icon: Icons.lock_outline,
            message: 'Đăng nhập tài khoản backend để tải mục tiêu thao tác.',
          )
        : !sessionMatches
        ? const _ActionTargetsMessage(
            icon: Icons.sync_problem_outlined,
            message:
                'Phiên backend đã thay đổi. Đóng hộp thoại rồi mở lại để tải mục tiêu mới.',
          )
        : _buildTargets(ref, session);

    final availableHeight = media.size.height - media.viewInsets.vertical - 136;
    final contentHeight = availableHeight
        .clamp(120.0, media.size.height * 0.68)
        .toDouble();
    final contentWidth = (media.size.width - 72).clamp(0.0, 560.0).toDouble();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: const Text('Chọn vị thế tài khoản backend'),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: ListView(
          key: const Key('backend-action-dialog-scroll'),
          padding: EdgeInsets.zero,
          children: [
            Text(
              session == null
                  ? 'Các mục tiêu này được tải từ tài khoản backend.'
                  : 'Tài khoản backend: ${session.accountIdentifier}',
              key: const Key('backend-action-account-label'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Danh sách dưới đây thuộc tài khoản backend. Ứng dụng không ghép các mục này với số dư hoặc vị thế OKX đang hiển thị.',
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }

  Widget _buildTargets(WidgetRef ref, TradeSession session) {
    final positionsAsync = ref.watch(tradePositionsProvider);
    return positionsAsync.when(
      skipLoadingOnReload: false,
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => _ActionTargetsMessage(
        icon: Icons.error_outline,
        message: 'Không thể tải mục tiêu backend: $error',
      ),
      data: (snapshot) {
        final current = ref.read(tradeSessionProvider);
        final backendSession = ref.read(backendDataSessionProvider);
        if (!_sameSession(current.session, session) ||
            !current.isAuthenticated ||
            !backendSession.matches(expectedGeneration, session) ||
            snapshot.accountIdentifier != session.accountIdentifier) {
          return const _ActionTargetsMessage(
            icon: Icons.sync_problem_outlined,
            message:
                'Tài khoản hoặc phiên backend đã thay đổi. Đóng hộp thoại rồi mở lại.',
          );
        }
        if (snapshot.positions.isEmpty) {
          return const _ActionTargetsMessage(
            icon: Icons.inbox_outlined,
            message: 'Tài khoản backend chưa có vị thế đủ điều kiện.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final position in snapshot.positions)
              _BackendPositionTargetCard(position: position),
          ],
        );
      },
    );
  }

  bool _sameSession(TradeSession? current, TradeSession expected) =>
      current != null &&
      current.bearerToken == expected.bearerToken &&
      current.accountIdentifier == expected.accountIdentifier &&
      current.expiresAt == expected.expiresAt;
}

class _BackendPositionTargetCard extends StatelessWidget {
  const _BackendPositionTargetCard({required this.position});

  final OkxPosition position;

  @override
  Widget build(BuildContext context) {
    final side = position.posSide.isEmpty
        ? position.direction
        : position.posSide;
    final size = position.size.isEmpty ? position.pos : position.size;
    return Card(
      key: ValueKey(
        jsonEncode([
          position.identity,
          position.instId,
          position.instType,
          position.posSide,
          position.mgnMode,
          size,
        ]),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              position.instId,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${position.instType} · ${side.isEmpty ? '—' : side} · ${size.isEmpty ? '—' : size}',
              key: const Key('backend-action-target-authority'),
            ),
            PositionActionControls(position: position),
          ],
        ),
      ),
    );
  }
}

class _ActionTargetsMessage extends StatelessWidget {
  const _ActionTargetsMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 30),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}
