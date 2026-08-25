import 'package:flutter/material.dart';

import 'kaj_design_tokens.dart';

abstract final class KajComponentTokens {
  static const double controlHeight = 46;
  static const double compactControlHeight = 38;
  static const double appHeaderHeight = 68;
  static const double sidebarExpandedWidth = 264;
  static const double sidebarCollapsedWidth = 82;
  static const double dialogMaxWidth = 1040;
  static const double dialogCompactMaxWidth = 720;
  static const EdgeInsets pagePadding = EdgeInsets.all(24);
  static const EdgeInsets compactPagePadding = EdgeInsets.all(14);
  static const EdgeInsets cardPadding = EdgeInsets.all(20);
  static const EdgeInsets dialogPadding = EdgeInsets.all(24);

  static BorderRadius get cardRadius =>
      BorderRadius.circular(KajDesignTokens.radiusLg);
  static BorderRadius get controlRadius =>
      BorderRadius.circular(KajDesignTokens.radiusSm);
}
