import 'package:flutter/material.dart';
import '../../core/exchange/exchange_models.dart';
import 'connections_screen.dart';

class ConnectionCatalogScreen extends StatelessWidget {
  const ConnectionCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thêm kết nối')),
    body: ListView(
      children: [
        for (final exchange in ExchangeId.values)
          ListTile(
            title: Text(exchange == ExchangeId.okx ? 'OKX' : 'Binance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => connectionForm(exchange)),
            ),
          ),
        const ListTile(enabled: false, title: Text('Sàn khác')),
      ],
    ),
  );
}
