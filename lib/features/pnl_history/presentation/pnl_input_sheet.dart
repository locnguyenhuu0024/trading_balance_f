// File Name: pnl_input_sheet.dart
// File Path: lib/features/pnl_history/presentation/pnl_input_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/pnl_model.dart';
import '../data/pnl_repository.dart';

void showPnlInputSheet(BuildContext context, bool isDark) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PnlInputSheet(isDark: isDark),
  );
}

class PnlInputSheet extends ConsumerStatefulWidget {
  final bool isDark;
  const PnlInputSheet({super.key, required this.isDark});

  @override
  ConsumerState<PnlInputSheet> createState() => _PnlInputSheetState();
}

class _PnlInputSheetState extends ConsumerState<PnlInputSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isProfit = true;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _savePnl() async {
    setState(() {
      _errorMessage = null;
    });

    final amountText = _amountController.text.replaceAll(',', '.');
    final rawAmount = double.tryParse(amountText);

    if (rawAmount == null || rawAmount <= 0) {
      setState(() => _errorMessage = 'Vui lòng nhập số tiền hợp lệ!');
      return;
    }

    setState(() => _isLoading = true);

    final finalAmount = _isProfit ? rawAmount : -rawAmount;

    final newPnl = RealizedPnl(
      amount: finalAmount,
      note: _noteController.text,
      timestamp: DateTime.now(),
    );

    try {
      await ref.read(pnlRepositoryProvider).addRealizedPnl(newPnl).timeout(const Duration(seconds: 7));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã lưu lịch sử PnL thành công!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e.toString().contains('TimeoutException')) {
            _errorMessage = 'Không thể kết nối tới Firebase (Quá thời gian chờ). Vui lòng kiểm tra lại cấu hình!';
          } else {
            _errorMessage = 'Lỗi lưu dữ liệu: $e';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black;
    final hintColor = widget.isDark ? Colors.grey.shade500 : Colors.grey.shade400;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nhật ký Chốt lệnh', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.redAccent)),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],

            // --- Chọn Lãi / Lỗ ---
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isProfit = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isProfit ? Colors.green.withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _isProfit ? Colors.green : Colors.grey.shade300),
                      ),
                      alignment: Alignment.center,
                      child: Text('LÃI (PROFIT)', style: TextStyle(color: _isProfit ? Colors.green : hintColor, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isProfit = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isProfit ? Colors.redAccent.withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: !_isProfit ? Colors.redAccent : Colors.grey.shade300),
                      ),
                      alignment: Alignment.center,
                      child: Text('LỖ (LOSS)', style: TextStyle(color: !_isProfit ? Colors.redAccent : hintColor, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- Số tiền ---
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: _isProfit ? Colors.green : Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Số tiền (USDT)',
                prefixText: _isProfit ? '+ \$' : '- \$',
                prefixStyle: TextStyle(color: _isProfit ? Colors.green : Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // --- Ghi chú ---
            TextField(
              controller: _noteController,
              style: TextStyle(color: textColor),
              decoration: const InputDecoration(
                labelText: 'Ghi chú (Tâm lý, lý do chốt...)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // --- Nút Lưu ---
            ElevatedButton(
              onPressed: _isLoading ? null : _savePnl,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.isDark ? Colors.white : Colors.black,
                foregroundColor: widget.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.grey, strokeWidth: 2))
                  : const Text('GHI VÀO NHẬT KÝ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}