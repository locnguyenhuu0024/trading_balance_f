import 'package:flutter/material.dart';

import '../exchange/exchange_models.dart';

/// Small local exchange mark with an accessible source name. The painter uses
/// primitive shapes so account views do not depend on remote or package icons.
class ExchangeIcon extends StatelessWidget {
  const ExchangeIcon({super.key, required this.source, this.size = 20});

  final ExchangeSource source;
  final double size;

  String get _name => switch (source) {
    ExchangeSource.okx => 'OKX',
    ExchangeSource.binance => 'Binance',
  };

  @override
  Widget build(BuildContext context) {
    final color = source == ExchangeSource.binance
        ? const Color(0xFFF0B90B)
        : Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: _name,
      child: Semantics(
        label: '$_name exchange',
        image: true,
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(painter: _ExchangeMarkPainter(source, color)),
          ),
        ),
      ),
    );
  }
}

class _ExchangeMarkPainter extends CustomPainter {
  const _ExchangeMarkPainter(this.source, this.color);

  final ExchangeSource source;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 8;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (source == ExchangeSource.binance) {
      _diamond(canvas, center, unit * 1.45, paint);
      _diamond(canvas, center.translate(0, -unit * 2.4), unit, paint);
      _diamond(canvas, center.translate(unit * 2.4, 0), unit, paint);
      _diamond(canvas, center.translate(0, unit * 2.4), unit, paint);
      _diamond(canvas, center.translate(-unit * 2.4, 0), unit, paint);
      return;
    }

    final block = unit * 1.7;
    final gap = unit * 0.55;
    final x = center.dx - block - gap / 2;
    final y = center.dy - block - gap / 2;
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 2; column++) {
        canvas.drawRect(
          Rect.fromLTWH(
            x + column * (block + gap),
            y + row * (block + gap),
            block,
            block,
          ),
          paint,
        );
      }
    }
  }

  void _diamond(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ExchangeMarkPainter oldDelegate) =>
      oldDelegate.source != source || oldDelegate.color != color;
}
