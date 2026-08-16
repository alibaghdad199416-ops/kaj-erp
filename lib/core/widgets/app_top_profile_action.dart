import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/pages/current_user_profile_page.dart';

import 'app_user_avatar.dart';

/// Profile entry point for layouts that use the horizontal top navigation.
///
/// The side-navigation workspace exposes the same action in
/// [AppWorkspaceTopBar]. Keeping a dedicated top-navigation action prevents
/// authenticated users from losing access to their profile when they switch
/// navigation modes or use a compact viewport.
class AppTopProfileAction extends StatelessWidget {
  const AppTopProfileAction({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AccessController>().currentUser;
    final ar = context.l10n.isArabic;
    final profileLabel = ar ? 'تعديل الملف الشخصي' : 'Edit profile';

    return Material(
      color: const Color(0xFF050B10),
      child: SizedBox(
        width: 54,
        height: 68,
        child: Center(
          child: Tooltip(
            key: const ValueKey('quality-line-profile-tooltip-button-v2'),
            message: profileLabel,
            child: IconButton(
              onPressed: () => showCurrentUserProfileEditor(context),
              icon: ExcludeSemantics(
                child: AppUserAvatar(
                  radius: 18,
                  avatarBase64: user?.avatarBase64,
                  fallbackText: user?.fullName ?? (ar ? 'مستخدم' : 'User'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
