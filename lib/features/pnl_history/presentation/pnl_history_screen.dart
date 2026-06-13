// File Name: pnl_history_screen.dart
// File Path: lib/features/pnl_history/presentation/pnl_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'providers/pnl_provider.dart';
import '../../portfolio/presentation/portfolio_screen.dart'; // Lấy biến isDarkModeProvider

class PnlHistoryScreen extends ConsumerWidget {
  const PnlHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(isDarkModeProvider);
    final pnlStream = ref.watch(pnlHistoryStreamProvider);

    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    final textColor = isDark ? Colors.white : Colors.black;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text('Nhật ký Giao dịch', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: pnlStream.when(
        loading: () => Center(child: CircularProgressIndicator(color: textColor)),
        error: (err, stack) => Center(child: Text('Lỗi tải dữ liệu:\n$err', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))),
        data: (pnlList) {
          if (pnlList.isEmpty) {
            return Center(child: Text('Chưa có dữ liệu chốt lời/lỗ.', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)));
          }

          // Tính toán số liệu tổng
          double totalProfit = 0;
          double totalLoss = 0;
          for (var p in pnlList) {
            if (p.amount >= 0) {
              totalProfit += p.amount;
            } else {
              totalLoss += p.amount;
            }
          }
          final netPnl = totalProfit + totalLoss;
          final currencyFormat = NumberFormat("#,##0.00", "en_US");

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Khối Thống kê Tổng Quát ---
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                  boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    Text('TỔNG LỢI NHUẬN THỰC TẾ', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      '${netPnl >= 0 ? '+' : ''}\$${currencyFormat.format(netPnl)}',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: netPnl >= 0 ? Colors.green : Colors.redAccent, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            Text('Tổng Lãi', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            Text('+\$${currencyFormat.format(totalProfit)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        Container(width: 1, height: 36, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                        Column(
                          children: [
                            Text('Tổng Lỗ', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            Text('-\$${currencyFormat.format(totalLoss.abs())}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                          ],
                        ),
                      ],
                    )
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Lịch sử chi tiết', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
              ),

              // --- Bảng Chi tiết ---
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                      dataRowColor: WidgetStateProperty.all(cardColor),
                      dividerThickness: 0.5,
                      columnSpacing: 32,
                      columns: [
                        DataColumn(label: Text('Thời gian', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13))),
                        DataColumn(label: Text('Lãi / Lỗ (USDT)', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13)), numeric: true),
                        DataColumn(label: Text('Ghi chú', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13))),
                      ],
                      rows: pnlList.map((pnl) {
                        final isProfit = pnl.amount >= 0;
                        return DataRow(
                          cells: [
                            DataCell(Text(DateFormat('dd/MM/yy HH:mm').format(pnl.timestamp.toLocal()), style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.grey.shade700, fontSize: 12))),
                            DataCell(Text(
                              '${isProfit ? '+' : ''}${currencyFormat.format(pnl.amount)}',
                              style: TextStyle(color: isProfit ? Colors.green : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            )),
                            DataCell(Text(pnl.note.isEmpty ? '--' : pnl.note, style: TextStyle(color: textColor, fontSize: 12))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}