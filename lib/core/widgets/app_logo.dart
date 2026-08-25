import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Official Khat Al-Jawda mark used across login, navigation and splash.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.width = 230,
    this.height,
    this.borderRadius = 18,
    this.padding = EdgeInsets.zero,
    this.showShadow = false,
  });

  final double width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = height ?? width * .62;
    final brightness = Theme.of(context).brightness;

    return Container(
      width: width,
      height: effectiveHeight,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: KajDesignTokens.champagne.withValues(alpha: .32),
        ),
        boxShadow: showShadow
            ? KajDesignTokens.accentShadow(
                brightness,
                accent: KajDesignTokens.champagne,
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PositionedDirectional(
            top: -45,
            end: -30,
            child: Container(
              width: effectiveHeight,
              height: effectiveHeight,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    KajDesignTokens.electricBlue.withValues(alpha: .13),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(effectiveHeight * .07),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => const Center(
                child: AppText(
                  'KHAT AL JAWDA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
