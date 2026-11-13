import 'package:flutter/material.dart';

class CryptoIconUrls {
  static const _githubRawBase =
      'https://raw.githubusercontent.com/spothq/cryptocurrency-icons/master/128/color';

  static const Map<String, List<String>> _fallbackUrls = {
    'btc': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/bitcoin/info/logo.png',
    ],
    'eth': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/info/logo.png',
    ],
    'bnb': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/smartchain/info/logo.png',
    ],
    'sol': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/solana/info/logo.png',
      'https://coin-images.coingecko.com/coins/images/4128/large/solana.png',
    ],
    'trx': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/tron/info/logo.png',
    ],
    'ton': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ton/info/logo.png',
      'https://coin-images.coingecko.com/coins/images/17980/large/ton_symbol.png',
    ],
    'sui': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/sui/info/logo.png',
      'https://coin-images.coingecko.com/coins/images/26375/large/sui-ocean-square.png',
    ],
    'apt': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/aptos/info/logo.png',
      'https://coin-images.coingecko.com/coins/images/26455/large/aptos_round.png',
    ],
    'near': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/near/info/logo.png',
      'https://coin-images.coingecko.com/coins/images/10365/large/near.jpg',
    ],
    'avax': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/avalanchec/info/logo.png',
    ],
    'matic': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/polygon/info/logo.png',
    ],
    'pol': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/polygon/info/logo.png',
    ],
    'atom': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/cosmos/info/logo.png',
    ],
    'fil': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/filecoin/info/logo.png',
    ],
    'arb': [
      'https://coin-images.coingecko.com/coins/images/16547/large/arb.jpg',
    ],
    'op': [
      'https://coin-images.coingecko.com/coins/images/25244/large/Optimism.png',
    ],
    'icp': [
      'https://coin-images.coingecko.com/coins/images/14495/large/Internet_Computer_logo.png',
    ],
    'sei': [
      'https://coin-images.coingecko.com/coins/images/28205/large/Sei_Logo_-_Transparent.png',
    ],
    'tia': [
      'https://coin-images.coingecko.com/coins/images/31967/large/tia.jpg',
    ],
    'usdt': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xdAC17F958D2ee523a2206206994597C13D831ec7/logo.png',
      'https://coin-images.coingecko.com/coins/images/325/large/Tether.png',
    ],
    'usdc': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48/logo.png',
      'https://coin-images.coingecko.com/coins/images/6319/large/usdc.png',
    ],
    'dai': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x6B175474E89094C44Da98b954EedeAC495271d0F/logo.png',
    ],
    'wbtc': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599/logo.png',
    ],
    'link': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x514910771AF9Ca656af840dff83E8264EcF986CA/logo.png',
    ],
    'uni': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984/logo.png',
    ],
    'aave': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9/logo.png',
    ],
    'shib': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE/logo.png',
    ],
    'pepe': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x6982508145454Ce325dDbE47a25d4ec3d2311933/logo.png',
    ],
    'okb': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x75231F58b43240C9718Dd58B4967c5114342a86c/logo.png',
    ],
    'crv': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xD533a949740bb3306d119CC777fa900bA034cd52/logo.png',
    ],
    'sand': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x3845badAde8e6dFF049820680d1F14bD3903a5d0/logo.png',
    ],
    'mana': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x0F5D2fB29fb7d3CFeE444a200298f468908cC942/logo.png',
    ],
    'grt': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xc944E90C64B2c07662A292be6244BDf05Cda44a7/logo.png',
    ],
    'ape': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x4d224452801ACEd8B2F0aebe155379bb5D594381/logo.png',
    ],
    'ldo': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32/logo.png',
    ],
    'imx': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xF57e7e7C23978C3cAeC3C3548E3D615c346e79fF/logo.png',
    ],
    'rndr': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24/logo.png',
    ],
    'gala': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xd1d2Eb1B1e90B638588728b4130137D262C87cae/logo.png',
    ],
    'comp': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xc00e94Cb662C3520282E6f5717214004A7f26888/logo.png',
    ],
    'sushi': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x6B3595068778DD592e39A122f4f5a5cF09C90fE2/logo.png',
    ],
    'snx': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xC011A73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F/logo.png',
    ],
    'bat': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x0D8775F648430679A709E98d2b0Cb6250d2887EF/logo.png',
    ],
    'ens': [
      'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0xC18360217D8F7Ab5e7c516566761ea12Ce7F9D72/logo.png',
    ],
  };

  static String normalizeSymbol(String symbol) => symbol.trim().toLowerCase();

  static String githubRawUrl(String symbol) {
    final normalized = normalizeSymbol(symbol);
    return '$_githubRawBase/$normalized.png';
  }

  static List<String> forSymbol(String symbol) {
    final normalized = normalizeSymbol(symbol);
    if (normalized.isEmpty) return const [];

    return [githubRawUrl(normalized), ...?_fallbackUrls[normalized]];
  }
}

class CryptoIconFallback {
  static String letter(String symbol) {
    final trimmed = symbol.trim();
    if (trimmed.isEmpty) return '?';

    return trimmed.substring(0, 1).toUpperCase();
  }
}

class CryptoIcon extends StatefulWidget {
  const CryptoIcon({
    super.key,
    required this.symbol,
    required this.size,
    required this.backgroundColor,
    required this.textColor,
    required this.textSize,
  });

  final String symbol;
  final double size;
  final Color backgroundColor;
  final Color textColor;
  final double textSize;

  @override
  State<CryptoIcon> createState() => _CryptoIconState();
}

class _CryptoIconState extends State<CryptoIcon> {
  int _sourceIndex = 0;

  @override
  void didUpdateWidget(covariant CryptoIcon oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (CryptoIconUrls.normalizeSymbol(oldWidget.symbol) !=
        CryptoIconUrls.normalizeSymbol(widget.symbol)) {
      _sourceIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = CryptoIconUrls.forSymbol(widget.symbol);
    final sourceIndex = urls.isEmpty
        ? 0
        : _sourceIndex >= urls.length
        ? urls.length - 1
        : _sourceIndex;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: urls.isEmpty
          ? _buildFallbackText()
          : Image.network(
              urls[sourceIndex],
              key: ValueKey(urls[sourceIndex]),
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                if (sourceIndex < urls.length - 1) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _sourceIndex != sourceIndex) return;
                    setState(() => _sourceIndex += 1);
                  });
                }

                return _buildFallbackText();
              },
            ),
    );
  }

  Widget _buildFallbackText() {
    return Text(
      CryptoIconFallback.letter(widget.symbol),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: widget.textColor,
        fontSize: widget.textSize,
      ),
    );
  }
}
