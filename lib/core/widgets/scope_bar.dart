import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/connections/scope_picker.dart';
import '../exchange/exchange_models.dart';
import '../exchange/exchange_registry.dart';
import '../exchange/exchange_scope.dart';
import '../theme/app_theme.dart';

String scopeProductLine(ExchangeId exchange) => exchange == ExchangeId.okx
    ? 'Tài khoản giao dịch'
    : (kIsWeb ? 'USDⓈ-M' : 'USDⓈ-M · Spot · Margin');

class ScopeBar extends ConsumerWidget {
  const ScopeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(exchangeScopeProvider);
    final profile = ref
        .watch(exchangeRegistryProvider)
        .firstWhere((entry) => entry.profile.connectionId == scope.connectionId)
        .profile;
    void openPicker() => showModalBottomSheet<void>(
      context: context,
      builder: (_) => const ScopePicker(),
    );
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      onTap: openPicker,
      label: '${profile.label}, Chính',
      child: ExcludeSemantics(
        child: Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: palette.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: openPicker,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        profile.label.substring(0, 1),
                        style: TextStyle(
                          color: palette.onStrong,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${profile.label} / Chính',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            scopeProductLine(profile.exchange),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
