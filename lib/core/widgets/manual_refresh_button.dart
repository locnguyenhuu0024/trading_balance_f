import 'package:flutter/material.dart';

class ManualRefreshButton extends StatefulWidget {
  const ManualRefreshButton({
    super.key,
    required this.buttonKey,
    required this.onRefresh,
    this.isBusy = false,
  });

  final Key buttonKey;
  final Future<void> Function()? onRefresh;
  final bool isBusy;

  @override
  State<ManualRefreshButton> createState() => _ManualRefreshButtonState();
}

class _ManualRefreshButtonState extends State<ManualRefreshButton> {
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    if (_isRefreshing || widget.isBusy || refresh == null) return;
    setState(() => _isRefreshing = true);
    try {
      await refresh();
    } catch (_) {
      // The owning page renders its provider or storage error state.
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isRefreshing || widget.isBusy;
    return IconButton(
      key: widget.buttonKey,
      tooltip: 'Làm mới dữ liệu',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: widget.onRefresh == null || isBusy ? null : _refresh,
      icon: _isRefreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
  }
}
