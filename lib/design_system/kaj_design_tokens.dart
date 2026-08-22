import 'package:flutter/material.dart';

import 'package:quality_line_erp/app/brand_identity.dart';

/// Central design tokens for the KAJ luxury automotive ERP experience.
///
/// Keep business widgets free from hard-coded visual values. New screens should
/// consume these tokens so the light and dark themes remain visually aligned.
abstract final class KajDesignTokens {
  static const double radiusXs = 6;
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;

  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  static const Color darkCanvas = Color(0xFF03070A);
  static const Color darkWorkspace = Color(0xFF050B10);
  static const Color darkSurface = Color(0xFF091117);
  static const Color darkSurfaceRaised = Color(0xFF0F1921);
  static const Color darkSurfaceHighest = Color(0xFF15232D);
  static const Color darkBorder = Color(0xFF22333F);
  static const Color darkBorderStrong = Color(0xFF36505E);

  static const Color lightCanvas = Color(0xFFF1F3F4);
  static const Color lightWorkspace = Color(0xFFF6F7F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFFAFBFC);
  static const Color lightBorder = Color(0xFFD8DEE2);
  static const Color lightBorderStrong = Color(0xFFBCC6CC);

  static const Color pitchBlack = BrandIdentity.pitchBlack;
  static const Color plainWhite = BrandIdentity.plainWhite;
  static const Color electricBlue = BrandIdentity.electricBlue;
  static const Color success = BrandIdentity.staticGreen;
  static const Color staticGreen = success;
  static const Color champagne = BrandIdentity.sand;
  static const Color champagneGold = champagne;
  static const Color bronze = BrandIdentity.bronze;
  static const Color danger = Color(0xFFE45D5D);
  static const Color warning = Color(0xFFD7A94B);
  static const Color warningAmber = warning;

  static Color pageBackground(Brightness brightness) => workspace(brightness);

  static Color workspace(Brightness brightness) =>
      brightness == Brightness.dark ? darkWorkspace : lightWorkspace;

  static Color surface(Brightness brightness) =>
      brightness == Brightness.dark ? darkSurface : lightSurface;

  static Color raisedSurface(Brightness brightness) =>
      brightness == Brightness.dark ? darkSurfaceRaised : lightSurfaceRaised;

  static Color highestSurface(Brightness brightness) =>
      brightness == Brightness.dark
      ? darkSurfaceHighest
      : const Color(0xFFF0F3F5);

  static Color border(Brightness brightness) =>
      brightness == Brightness.dark ? darkBorder : lightBorder;

  static Color strongBorder(Brightness brightness) =>
      brightness == Brightness.dark ? darkBorderStrong : lightBorderStrong;

  static Color textPrimary(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFF4F7F8)
      : const Color(0xFF101416);

  static Color textSecondary(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFB8C3C8)
      : const Color(0xFF526168);

  static Color overlaySurface(Brightness brightness) => surface(
    brightness,
  ).withValues(alpha: brightness == Brightness.dark ? .94 : .97);

  static Color tableStripe(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF0C161D)
      : const Color(0xFFF7F9FA);

  /// Restrained enterprise elevation: enough separation for hierarchy without
  /// making every section look like a floating modal/card.
  static List<BoxShadow> softShadow(Brightness brightness) => <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(
        alpha: brightness == Brightness.dark ? .30 : .055,
      ),
      blurRadius: brightness == Brightness.dark ? 22 : 14,
      offset: Offset(0, brightness == Brightness.dark ? 9 : 6),
    ),
  ];

  static List<BoxShadow> accentShadow(
    Brightness brightness, {
    Color accent = electricBlue,
  }) => <BoxShadow>[
    BoxShadow(
      color: accent.withValues(
        alpha: brightness == Brightness.dark ? .15 : .075,
      ),
      blurRadius: 20,
      offset: const Offset(0, 7),
    ),
  ];

  static LinearGradient surfaceGradient(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const <Color>[Color(0xFF111D25), darkSurface]
          : const <Color>[Colors.white, Color(0xFFFBFCFC)],
    );
  }

  static LinearGradient primaryGradient(Brightness brightness) =>
      LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: <Color>[
          electricBlue,
          brightness == Brightness.dark
              ? const Color(0xFF197D86)
              : const Color(0xFF3B9DA4),
        ],
      );

  static LinearGradient premiumGradient(Brightness brightness) =>
      LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: <Color>[
          champagne,
          brightness == Brightness.dark ? bronze : const Color(0xFFAA925F),
        ],
      );
}
