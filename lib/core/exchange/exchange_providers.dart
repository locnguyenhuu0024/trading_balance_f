import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'binance_exchange_reader.dart';
import 'exchange_models.dart';
import 'exchange_readers.dart';
import 'okx_exchange_reader.dart';

final exchangeReadersProvider = Provider<List<ExchangeReader>>((ref) {
  return List<ExchangeReader>.unmodifiable(<ExchangeReader>[
    ref.watch(okxExchangeReaderProvider),
    ref.watch(binanceExchangeReaderProvider),
  ]);
});

final exchangeReaderProvider = Provider.family<ExchangeReader, ExchangeSource>((
  ref,
  source,
) {
  return switch (source) {
    ExchangeSource.okx => ref.watch(okxExchangeReaderProvider),
    ExchangeSource.binance => ref.watch(binanceExchangeReaderProvider),
  };
});
