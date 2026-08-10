import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Application-wide V4 automotive workspace background.
///
/// The approved references use a nearly black showroom canvas with faint
/// cyan/champagne geometry. This painter recreates the atmosphere without
/// embedding any sample vehicles, customers, suppliers, or users, so all
/// entity imagery remains dynamic and record-driven.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(
          color: dark
              ? KajDesignTokens.darkCanvas
              : KajDesignTokens.lightWorkspace,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                dark
                    ? 'assets/images/app_background_dark.png'
                    : 'assets/images/app_background_light.png',
              ),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              opacity: dark ? .20 : .15,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(painter: _KajV4GeometryPainter(dark: dark)),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(.76, -.82),
              radius: 1.18,
              colors: <Color>[
                KajDesignTokens.electricBlue.withValues(
                  alpha: dark ? .11 : .055,
                ),
                Colors.transparent,
              ],
              stops: const <double>[0, .72],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? <Color>[
                      Colors.black.withValues(alpha: .05),
                      Colors.black.withValues(alpha: .42),
                    ]
                  : <Color>[
                      Colors.white.withValues(alpha: .44),
                      Colors.white.withValues(alpha: .78),
                    ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _KajV4GeometryPainter extends CustomPainter {
  const _KajV4GeometryPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final cyan = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = KajDesignTokens.electricBlue.withValues(
        alpha: dark ? .055 : .032,
      );
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = KajDesignTokens.champagne.withValues(alpha: dark ? .05 : .025);

    final spacing = math.max(120.0, size.width / 10);
    for (double x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * .62, size.height),
        cyan,
      );
      canvas.drawLine(
        Offset(x + size.height * .46, 0),
        Offset(x - size.height * .10, size.height),
        gold,
      );
    }

    final topPath = Path()
      ..moveTo(size.width * .66, 0)
      ..lineTo(size.width * .80, size.height * .12)
      ..lineTo(size.width * .73, size.height * .24)
      ..lineTo(size.width * .94, size.height * .39);
    canvas.drawPath(topPath, gold);

    final bottomPath = Path()
      ..moveTo(size.width * .06, size.height)
      ..lineTo(size.width * .20, size.height * .86)
      ..lineTo(size.width * .34, size.height)
      ..lineTo(size.width * .48, size.height * .84);
    canvas.drawPath(bottomPath, cyan);
  }

  @override
  bool shouldRepaint(covariant _KajV4GeometryPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
