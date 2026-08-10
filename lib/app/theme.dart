import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_layout_metrics.dart';
import 'package:quality_line_erp/core/widgets/luxury_page_transitions.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_typography.dart';

import 'brand_identity.dart';

class AppTheme {
  static const primary = BrandIdentity.electricBlue;
  static const hoverAccent = BrandIdentity.electricBlue;
  static const lightBackground = BrandIdentity.lightWorkspace;
  static const darkBackground = BrandIdentity.darkWorkspace;
  static const darkSurface = BrandIdentity.darkSurface;
  static const darkBorder = BrandIdentity.darkBorder;
  static const lightBorder = BrandIdentity.lightBorder;

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = KajDesignTokens.surface(brightness);
    final raisedSurface = KajDesignTokens.raisedSurface(brightness);
    final background = KajDesignTokens.workspace(brightness);
    final border = KajDesignTokens.border(brightness);
    final foreground = isDark
        ? BrandIdentity.plainWhite
        : const Color(0xFF101416);
    final muted = isDark ? const Color(0xFFA6B0B5) : const Color(0xFF5D686E);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: surface,
      error: BrandIdentity.danger,
    );
    final scheme = baseScheme.copyWith(
      primary: primary,
      onPrimary: const Color(0xFF001F22),
      primaryContainer: isDark
          ? const Color(0xFF10353A)
          : const Color(0xFFD9F5F6),
      onPrimaryContainer: isDark
          ? const Color(0xFFC9FBFD)
          : const Color(0xFF12383B),
      secondary: BrandIdentity.sand,
      onSecondary: const Color(0xFF201B10),
      secondaryContainer: isDark
          ? const Color(0xFF155A60)
          : const Color(0xFFF3E8CF),
      onSecondaryContainer: isDark ? Colors.white : const Color(0xFF44391F),
      tertiary: BrandIdentity.staticGreen,
      onTertiary: const Color(0xFF002116),
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: muted,
      outline: KajDesignTokens.strongBorder(brightness),
      outlineVariant: border,
      surfaceContainerLowest: isDark
          ? KajDesignTokens.darkCanvas
          : Colors.white,
      surfaceContainerLow: surface,
      surfaceContainer: raisedSurface,
      surfaceContainerHigh: KajDesignTokens.highestSurface(brightness),
      surfaceContainerHighest: isDark
          ? const Color(0xFF16232C)
          : const Color(0xFFE9EEF1),
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final roundedButton = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
    );
    final roundedField = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
      borderSide: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      visualDensity: VisualDensity.compact,
      fontFamily: KajTypography.primaryFamily,
      fontFamilyFallback: KajTypography.fallbackFamilies,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: surface,
      cardColor: surface,
      disabledColor: foreground.withValues(alpha: .32),
      hoverColor: primary.withValues(alpha: isDark ? .10 : .075),
      focusColor: primary.withValues(alpha: isDark ? .16 : .12),
      highlightColor: primary.withValues(alpha: isDark ? .08 : .055),
      splashFactory: InkRipple.splashFactory,
      textTheme: KajTypography.theme(foreground, muted),
      appBarTheme: AppBarTheme(
        backgroundColor: (isDark ? const Color(0xFF071017) : Colors.white)
            .withValues(alpha: .94),
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -.15,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: isDark ? .42 : .08),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF0E1B23).withValues(alpha: .92)
            : Colors.white.withValues(alpha: .94),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppLayoutMetrics.fieldVerticalPadding + 1,
        ),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFFE8F2F5) : const Color(0xFF17262D),
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
        floatingLabelStyle: TextStyle(
          color: isDark ? const Color(0xFF9DE7EA) : const Color(0xFF0A5660),
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFFB6C7CC) : const Color(0xFF53666E),
          fontSize: 12.5,
        ),
        prefixIconColor: isDark
            ? const Color(0xFFA9C2C8)
            : const Color(0xFF455A64),
        suffixIconColor: isDark
            ? const Color(0xFFA9C2C8)
            : const Color(0xFF455A64),
        border: roundedField,
        enabledBorder: roundedField,
        focusedBorder: roundedField.copyWith(
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: roundedField.copyWith(
          borderSide: const BorderSide(color: BrandIdentity.danger),
        ),
        focusedErrorBorder: roundedField.copyWith(
          borderSide: const BorderSide(color: BrandIdentity.danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(40, 42)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          ),
          shape: WidgetStatePropertyAll(roundedButton),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return foreground.withValues(alpha: .10);
            }
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFF78D0D3);
            }
            return primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return foreground.withValues(alpha: .35);
            }
            return const Color(0xFF061214);
          }),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: .08),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: const Color(0xFF061214),
          shape: roundedButton,
          minimumSize: const Size(40, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(40, 42)),
          shape: WidgetStatePropertyAll(roundedButton),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: .08)),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.hovered) ? primary : border,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? foreground.withValues(alpha: .35)
                : (isDark || states.contains(WidgetState.hovered))
                ? primary
                : foreground,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(roundedButton),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: .08)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? foreground.withValues(alpha: .35)
                : (isDark || states.contains(WidgetState.hovered))
                ? primary
                : foreground,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
            ),
          ),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: .10)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => isDark || states.contains(WidgetState.hovered)
                ? primary
                : muted,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            surface.withValues(alpha: .98),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: AppLayoutMetrics.tableHeadingHeight + 2,
        dataRowMinHeight: AppLayoutMetrics.tableRowMinHeight + 2,
        dataRowMaxHeight: AppLayoutMetrics.tableRowMaxHeight + 4,
        horizontalMargin: 16,
        columnSpacing: 22,
        dividerThickness: 1,
        headingRowColor: WidgetStatePropertyAll(
          raisedSurface.withValues(alpha: isDark ? .80 : .95),
        ),
        dataRowColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? primary.withValues(alpha: isDark ? .055 : .045)
              : Colors.transparent,
        ),
        headingTextStyle: TextStyle(
          color: muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .08,
        ),
        dataTextStyle: TextStyle(color: foreground, fontSize: 12.5),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        constraints: const BoxConstraints(
          minWidth: 380,
          maxWidth: 720,
          minHeight: 180,
          maxHeight: 720,
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        contentTextStyle: TextStyle(
          color: foreground,
          fontSize: 13,
          height: 1.45,
        ),
        backgroundColor: (isDark ? const Color(0xFF0B1820) : Colors.white)
            .withValues(alpha: .97),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(KajDesignTokens.radiusLg),
          ),
          side: BorderSide(color: border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF202A2F) : const Color(0xFF202426),
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusXs),
          border: Border.all(color: primary.withValues(alpha: .25)),
        ),
        textStyle: const TextStyle(fontSize: 11.5, color: Colors.white),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: isDark
            ? const Color(0xFF182126)
            : const Color(0xFF1A2023),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
          side: BorderSide(color: primary.withValues(alpha: .22)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(8),
        thumbVisibility: const WidgetStatePropertyAll(false),
        trackVisibility: const WidgetStatePropertyAll(false),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? primary.withValues(alpha: .72)
              : muted.withValues(alpha: .34),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        checkColor: const WidgetStatePropertyAll(Color(0xFF061214)),
      ),
      radioTheme: RadioThemeData(
        visualDensity: VisualDensity.compact,
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : muted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF061214)
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? const Color(0xFF10232D)
            : const Color(0xFFF1F7F8),
        selectedColor: primary.withValues(alpha: isDark ? .24 : .18),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusXs),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        labelStyle: TextStyle(
          color: foreground,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: raisedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
          side: BorderSide(color: border),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(raisedSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: .14),
        elevation: 0,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: .14),
        selectedIconTheme: const IconThemeData(color: primary),
        selectedLabelTextStyle: const TextStyle(
          color: primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: LuxuryPageTransitionsBuilder(),
          TargetPlatform.iOS: LuxuryPageTransitionsBuilder(),
          TargetPlatform.windows: LuxuryPageTransitionsBuilder(),
          TargetPlatform.linux: LuxuryPageTransitionsBuilder(),
          TargetPlatform.macOS: LuxuryPageTransitionsBuilder(),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[
        AppSemanticColors(
          workspaceBackground: background,
          border: border,
          success: BrandIdentity.staticGreen,
          warning: BrandIdentity.sand,
          info: primary,
          premium: BrandIdentity.sand,
          danger: BrandIdentity.danger,
          raisedSurface: raisedSurface,
        ),
      ],
    );
  }
}

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.workspaceBackground,
    required this.border,
    required this.success,
    required this.warning,
    required this.info,
    required this.premium,
    required this.danger,
    required this.raisedSurface,
  });

  final Color workspaceBackground;
  final Color border;
  final Color success;
  final Color warning;
  final Color info;
  final Color premium;
  final Color danger;
  final Color raisedSurface;

  @override
  AppSemanticColors copyWith({
    Color? workspaceBackground,
    Color? border,
    Color? success,
    Color? warning,
    Color? info,
    Color? premium,
    Color? danger,
    Color? raisedSurface,
  }) => AppSemanticColors(
    workspaceBackground: workspaceBackground ?? this.workspaceBackground,
    border: border ?? this.border,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    premium: premium ?? this.premium,
    danger: danger ?? this.danger,
    raisedSurface: raisedSurface ?? this.raisedSurface,
  );

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      workspaceBackground: Color.lerp(
        workspaceBackground,
        other.workspaceBackground,
        t,
      )!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      premium: Color.lerp(premium, other.premium, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      raisedSurface: Color.lerp(raisedSurface, other.raisedSurface, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}
