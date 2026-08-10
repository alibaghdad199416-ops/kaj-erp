import 'package:flutter/material.dart';

import 'kaj_design_tokens.dart';

/// A restrained automotive motif derived from the angular rhythm of the KAJ
/// mark. It is intentionally decorative and ignores pointer events.
class KajBrandMotif extends StatelessWidget {
  const KajBrandMotif({
    super.key,
    this.opacity = .08,
    this.alignment = AlignmentDirectional.centerEnd,
    this.accent,
  });

  final double opacity;
  final AlignmentGeometry alignment;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? KajDesignTokens.electricBlue;
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Opacity(
          opacity: opacity.clamp(0, 1),
          child: CustomPaint(
            size: const Size(420, 220),
            painter: _KajMotifPainter(color),
          ),
        ),
      ),
    );
  }
}

class _KajMotifPainter extends CustomPainter {
  const _KajMotifPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;
    final fill = Paint()
      ..color = color.withValues(alpha: .20)
      ..style = PaintingStyle.fill;

    for (var row = 0; row < 3; row++) {
      final y = 34.0 + row * 65;
      for (var i = 0; i < 5; i++) {
        final x = 18.0 + i * 78 + (row.isOdd ? 28 : 0);
        final path = Path()
          ..moveTo(x, y + 24)
          ..lineTo(x + 24, y)
          ..lineTo(x + 62, y)
          ..lineTo(x + 38, y + 24)
          ..lineTo(x + 62, y + 48)
          ..lineTo(x + 24, y + 48)
          ..close();
        canvas.drawPath(path, i == 2 && row == 1 ? fill : stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KajMotifPainter oldDelegate) =>
      oldDelegate.color != color;
}
