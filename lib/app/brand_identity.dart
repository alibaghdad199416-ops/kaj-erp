import 'package:flutter/material.dart';

/// Official Khat Al-Jawda (KAJ) visual identity tokens.
/// Values are derived from KAJ Brand Guidelines 1.0 and extended with neutral
/// UI surfaces that preserve the official black, white, turquoise and
/// champagne identity in both application themes.
abstract final class BrandIdentity {
  static const pitchBlack = Color(0xFF000000);
  static const plainWhite = Color(0xFFFFFFFF);
  static const graphite = Color(0xFF6D6E71);
  static const silver = Color(0xFFC8C8CA);
  static const bronze = Color(0xFF83734D);
  static const sand = Color(0xFFCEB686);
  static const electricBlue = Color(0xFF62BEC1);
  static const staticGreen = Color(0xFF00D17D);

  static const lightWorkspace = Color(0xFFF5F7F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceRaised = Color(0xFFFAFBFC);
  static const lightBorder = Color(0xFFD8DEE2);

  static const darkWorkspace = Color(0xFF080B0D);
  static const darkSurface = Color(0xFF0E1317);
  static const darkSurfaceRaised = Color(0xFF141B20);
  static const darkBorder = Color(0xFF263238);

  static const danger = Color(0xFFE45D5D);
  static const warning = Color(0xFFD7A94B);

  static const String productName = 'KAJ ERP';
  static const String companyNameEn = 'Khat Al-Jawda';
  static const String companyNameAr = 'خط الجودة';
}
