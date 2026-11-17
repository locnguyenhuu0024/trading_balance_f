import 'package:flutter/material.dart';
import '../../core/exchange/exchange_models.dart';
import 'connections_screen.dart';

class ConnectionCatalogScreen extends StatelessWidget {
  const ConnectionCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Row(
            children: [
              BackButton(),
              Expanded(
                child: Text(
                  'Thêm kết nối',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          for (final exchange in ExchangeId.values)
            ListTile(
              title: Text(exchange == ExchangeId.okx ? 'OKX' : 'Binance'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => connectionForm(exchange),
                ),
              ),
            ),
          const ListTile(enabled: false, title: Text('Sàn khác')),
        ],
      ),
    ),
  );
}
