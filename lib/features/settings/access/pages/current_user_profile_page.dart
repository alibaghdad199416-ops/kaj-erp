import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_entry_components.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

Future<bool?> showCurrentUserProfileEditor(BuildContext context) {
  final controller = context.read<AccessController>();
  final user = controller.currentUser;
  if (user == null) return Future<bool?>.value(false);

  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: user.fullName);
  final phoneController = TextEditingController(text: user.phone);
  String? avatarBase64 = user.avatarBase64;
  bool saving = false;

  return showAppModuleDialog<bool>(
    context: context,
    title: context.l10n.isArabic ? 'الملف الشخصي' : 'My profile',
    builder: (pageContext) => StatefulBuilder(
      builder: (context, setState) {
        final Uint8List? avatarBytes = AppImageService.decodeBase64(
          avatarBase64,
        );

        Future<void> pickAvatar() async {
          try {
            final image = await AppImageService.pickAndProcess(
              maxWidth: 384,
              maxHeight: 384,
              quality: 76,
              maxOutputBytes: 180 * 1024,
            );
            if (image == null || !context.mounted) return;
            setState(() => avatarBase64 = image.base64);
          } catch (error) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: AppText(
                  context.l10n.isArabic
                      ? 'تعذر معالجة الصورة. اختر صورة JPG أو PNG أصغر.'
                      : 'The image could not be processed. Choose a smaller JPG or PNG image.',
                ),
                backgroundColor: KajDesignTokens.danger,
              ),
            );
          }
        }

        Future<void> save() async {
          if (saving || !(formKey.currentState?.validate() ?? false)) return;
          setState(() => saving = true);
          try {
            await controller.updateMyProfile(
              fullName: nameController.text,
              phone: phoneController.text,
              avatarBase64: avatarBase64,
            );
            if (context.mounted) Navigator.pop(context, true);
          } catch (error) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: AppText(
                  userFacingError(error, isArabic: context.l10n.isArabic),
                ),
                backgroundColor: KajDesignTokens.danger,
              ),
            );
          } finally {
            if (context.mounted) setState(() => saving = false);
          }
        }

        final ar = context.l10n.isArabic;
        return Padding(
          padding: const EdgeInsets.all(4),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  KajProfileSummary(
                    name: nameController.text.trim().isEmpty
                        ? (ar ? 'مستخدم النظام' : 'System user')
                        : nameController.text.trim(),
                    role: user.jobTitle.trim().isNotEmpty
                        ? user.jobTitle.trim()
                        : (user.roleName.trim().isNotEmpty
                              ? user.roleName.trim()
                              : (ar ? 'مستخدم معتمد' : 'Authorized user')),
                    avatar: CircleAvatar(
                      radius: 34,
                      backgroundImage: avatarBytes == null
                          ? null
                          : MemoryImage(avatarBytes),
                      child: avatarBytes == null
                          ? const Icon(Icons.person_outline_rounded, size: 30)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  KajShellSurface(
                    child: Column(
                      children: <Widget>[
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: <Widget>[
                            KajSecondaryAction(
                              onPressed: saving ? null : pickAvatar,
                              icon: Icons.photo_library_outlined,
                              label: ar ? 'تغيير الصورة' : 'Change photo',
                            ),
                            if (avatarBase64 != null)
                              KajSecondaryAction(
                                destructive: true,
                                onPressed: saving
                                    ? null
                                    : () => setState(() => avatarBase64 = null),
                                icon: Icons.delete_outline_rounded,
                                label: ar ? 'إزالة الصورة' : 'Remove photo',
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        KajField(
                          controller: nameController,
                          label: ar ? 'الاسم الكامل' : 'Full name',
                          leading: Icons.badge_outlined,
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? (ar ? 'الاسم مطلوب' : 'Name is required')
                              : null,
                        ),
                        const SizedBox(height: 12),
                        KajField(
                          controller: phoneController,
                          label: ar ? 'الهاتف' : 'Phone',
                          leading: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 8,
                    children: <Widget>[
                      KajSecondaryAction(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(context, false),
                        icon: Icons.close_rounded,
                        label: ar ? 'إلغاء' : 'Cancel',
                      ),
                      KajPrimaryAction(
                        onPressed: saving ? null : save,
                        busy: saving,
                        icon: Icons.save_outlined,
                        label: ar ? 'حفظ التغييرات' : 'Save changes',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ).whenComplete(() {
    nameController.dispose();
    phoneController.dispose();
  });
}
