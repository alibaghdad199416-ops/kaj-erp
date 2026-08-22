import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Removed unused import: 'package:quality_line_erp/app/brand_identity.dart'
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/design_system/kaj_brand_motif.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

import 'app_logo.dart';

/// Shared premium startup shell for splash, login and cloud-account screens.
/// The content API is intentionally stable so authentication logic remains
/// separate from the visual presentation.
class AppLaunchShell extends StatelessWidget {
  const AppLaunchShell({
    super.key,
    required this.content,
    this.topTrailing,
    this.contentMaxWidth = 520,
  });

  final Widget content;
  final Widget? topTrailing;
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: KajDesignTokens.workspace(brightness),
              image: DecorationImage(
                image: AssetImage(
                  dark
                      ? 'assets/images/app_background_dark.png'
                      : 'assets/images/app_background_light.png',
                ),
                fit: BoxFit.cover,
                opacity: dark ? .48 : .30,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: dark
                    ? <Color>[
                        const Color(0xFF030506).withValues(alpha: .96),
                        const Color(0xFF071225).withValues(alpha: .90),
                        const Color(0xFF020405).withValues(alpha: .96),
                      ]
                    : <Color>[
                        Colors.white.withValues(alpha: .95),
                        const Color(0xFFEAF1FF).withValues(alpha: .90),
                        Colors.white.withValues(alpha: .96),
                      ],
              ),
            ),
          ),
          const Positioned.fill(
            child: KajBrandMotif(
              opacity: .045,
              alignment: AlignmentDirectional.bottomEnd,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                final compact = constraints.maxWidth < 620;
                final formPanel = _LaunchFormPanel(
                  content: content,
                  contentMaxWidth: contentMaxWidth,
                  compact: compact,
                );

                return Stack(
                  children: <Widget>[
                    if (wide)
                      Row(
                        children: <Widget>[
                          const Expanded(flex: 11, child: _LaunchHeroPanel()),
                          Expanded(flex: 9, child: formPanel),
                        ],
                      )
                    else
                      formPanel,
                    if (topTrailing != null)
                      PositionedDirectional(
                        top: 16,
                        end: 16,
                        child: topTrailing!,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchHeroPanel extends StatelessWidget {
  const _LaunchHeroPanel();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ar = context.l10n.isArabic;
    final foreground = dark ? Colors.white : const Color(0xFF111719);
    final muted = foreground.withValues(alpha: .68);

    return Padding(
      padding: const EdgeInsets.all(34),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusXl),
          border: Border.all(
            color: KajDesignTokens.champagne.withValues(alpha: .24),
          ),
          boxShadow: KajDesignTokens.softShadow(
            dark ? Brightness.dark : Brightness.light,
          ),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: dark
                ? <Color>[
                    const Color(0xFF10171B).withValues(alpha: .96),
                    const Color(0xFF050809).withValues(alpha: .96),
                  ]
                : <Color>[
                    Colors.white.withValues(alpha: .96),
                    const Color(0xFFF1F4F5).withValues(alpha: .96),
                  ],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PositionedDirectional(
              top: -90,
              end: -70,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      KajDesignTokens.electricBlue.withValues(alpha: .16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: -120,
              start: -90,
              child: Transform.rotate(
                angle: -.32,
                child: Container(
                  width: 520,
                  height: 190,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: KajDesignTokens.champagne.withValues(alpha: .12),
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const AppLogo(
                    width: 238,
                    height: 148,
                    borderRadius: 18,
                    showShadow: false,
                  ),
                  const Spacer(),
                  AppText(
                    ar
                        ? 'إدارة متكاملة\nلتجارة السيارات'
                        : 'Integrated automotive\ncommerce management',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 38,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: ar ? -.4 : -1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppText(
                    ar
                        ? 'منصة موحدة للمبيعات والمشتريات والمخزون والصيانة والمحاسبة، مصممة لهوية خط الجودة.'
                        : 'A unified platform for sales, purchasing, inventory, maintenance and accounting, crafted for Khat Al-Jawda.',
                    style: TextStyle(
                      color: muted,
                      fontSize: 14.5,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: <Widget>[
                      _HeroFeature(
                        icon: Icons.directions_car_filled_outlined,
                        label: ar ? 'إدارة السيارات' : 'Vehicle management',
                      ),
                      _HeroFeature(
                        icon: Icons.inventory_2_outlined,
                        label: ar ? 'المخزون وقطع الغيار' : 'Inventory & parts',
                      ),
                      _HeroFeature(
                        icon: Icons.account_balance_wallet_outlined,
                        label: ar
                            ? 'المحاسبة والتقارير'
                            : 'Accounting & reports',
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 2,
                        color: KajDesignTokens.electricBlue,
                      ),
                      const SizedBox(width: 10),
                      AppText(
                        ar
                            ? 'خط الجودة للتجارة العامة والسيارات'
                            : 'Khat Al-Jawda General & Automotive Trade',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroFeature extends StatelessWidget {
  const _HeroFeature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: .045)
            : Colors.black.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: KajDesignTokens.border(Theme.of(context).brightness),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: KajDesignTokens.electricBlue),
          const SizedBox(width: 7),
          AppText(
            label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LaunchFormPanel extends StatelessWidget {
  const _LaunchFormPanel({
    required this.content,
    required this.contentMaxWidth,
    required this.compact,
  });

  final Widget content;
  final double contentMaxWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          compact ? 18 : 34,
          compact ? 76 : 48,
          compact ? 18 : 34,
          32,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (compact) ...<Widget>[
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppLogo(width: 178, height: 108, borderRadius: 16),
                ),
                const SizedBox(height: 24),
              ],
              AppText(
                ar ? 'مرحبًا بعودتك' : 'Welcome back',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: ar ? -.25 : -.7,
                ),
              ),
              const SizedBox(height: 8),
              AppText(
                ar
                    ? 'سجّل الدخول للوصول إلى مساحة عمل خط الجودة.'
                    : 'Sign in to access the Khat Al-Jawda workspace.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              content,
              const SizedBox(height: 20),
              AppText(
                SupabaseConfig.environmentLabel(isArabic: ar),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppLaunchContentPanel extends StatelessWidget {
  const AppLaunchContentPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: KajDesignTokens.surfaceGradient(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(color: KajDesignTokens.border(brightness)),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      child: child,
    );
  }
}

class AppLaunchPreferencesSwitch extends StatelessWidget {
  const AppLaunchPreferencesSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferencesController>();
    final brightness = Theme.of(context).brightness;
    final border = KajDesignTokens.border(brightness);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: KajDesignTokens.surfaceGradient(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        border: Border.all(color: border),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PopupMenuButton<Locale>(
            tooltip: context.l10n.text('language'),
            onSelected: preferences.setLocale,
            itemBuilder: (context) => const <PopupMenuEntry<Locale>>[
              PopupMenuItem<Locale>(
                value: Locale('ar'),
                child: AppText('العربية'),
              ),
              PopupMenuItem<Locale>(
                value: Locale('en'),
                child: AppText('English'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.language_rounded, size: 18),
                  const SizedBox(width: 7),
                  AppText(
                    preferences.isArabic ? 'AR' : 'EN',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 26, color: border),
          IconButton(
            tooltip: context.l10n.text('theme'),
            onPressed: preferences.toggleTheme,
            icon: Icon(
              preferences.isDarkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }
}
