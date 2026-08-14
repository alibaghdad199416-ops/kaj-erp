import 'dart:convert';
import 'dart:typed_data';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';
import 'package:quality_line_erp/design_system/kaj_admin_stage8_components.dart';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_floating_window.dart';
import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/models/audit_log_model.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_model.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_codes.dart';
import 'package:quality_line_erp/features/settings/access/models/user_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _query = '';
  String _auditQuery = '';
  String _auditOutcome = 'all';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = context.read<AccessController>();
      if (!controller.isLoading && controller.users.isEmpty) {
        await controller.loadAccess();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _runUserMutation(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editUser([UserModel? user]) async {
    final controller = context.read<AccessController>();
    if (user == null &&
        !controller.hasPermission(PermissionCodes.usersCreate)) {
      await controller.recordDeniedAccess(PermissionCodes.usersCreate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'إضافة المستخدمين متاحة لمدير النظام فقط.'
                : 'Only the system administrator can add users.',
          ),
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final fullNameController = TextEditingController(
      text: user?.fullName ?? '',
    );
    final usernameController = TextEditingController(
      text: user?.username ?? '',
    );
    final emailController = TextEditingController(text: user?.email ?? '');
    final phoneController = TextEditingController(text: user?.phone ?? '');
    final jobTitleController = TextEditingController(
      text: user?.jobTitle ?? '',
    );
    final passwordController = TextEditingController();

    String? defaultRoleId;
    for (final role in controller.roles) {
      if (role.id != 'role-admin') {
        defaultRoleId = role.id;
        break;
      }
    }
    defaultRoleId ??= controller.roles.isEmpty
        ? null
        : controller.roles.first.id;
    String? roleId = user?.roleId ?? defaultRoleId;
    bool isActive = user?.isActive ?? true;
    String? avatarBase64 = user?.avatarBase64;
    bool submitting = false;
    String? submitError;
    final writePermission = user == null ? 'users.create' : 'users.update';
    Widget securedField(String field, Widget child) => FieldPermissionControl(
      resource: 'users',
      field: field,
      viewPermission: 'users.view',
      writePermission: writePermission,
      child: child,
    );

    final saved = await showAppFloatingWindow<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final avatarBytes = _decodeAvatar(avatarBase64);

            Future<void> chooseAvatar() async {
              try {
                final image = await AppImageService.pickAndProcess(
                  maxWidth: 512,
                  maxHeight: 512,
                  quality: 78,
                  maxOutputBytes: 200 * 1024,
                );
                if (image == null || !context.mounted) return;
                setDialogState(() => avatarBase64 = image.base64);
              } on FormatException catch (error) {
                if (!context.mounted) return;
                final key =
                    error.message == 'image_input_too_large' ||
                        error.message == 'image_output_too_large'
                    ? 'userPhotoTooLarge'
                    : 'invalidUserPhoto';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: AppText(context.l10n.text(key)),
                    backgroundColor: Colors.red,
                  ),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: AppText(context.l10n.text('invalidUserPhoto')),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            Future<void> submitUser() async {
              if (submitting || !(formKey.currentState?.validate() ?? false)) {
                return;
              }
              final selectedRoleId = roleId;
              if (selectedRoleId == null) return;
              final matchingRoles = controller.roles
                  .where((role) => role.id == selectedRoleId)
                  .toList(growable: false);
              if (matchingRoles.isEmpty) {
                setDialogState(() {
                  submitError = context.l10n.isArabic
                      ? 'تعذر تحديد دور المستخدم. حدّث الصفحة وأعد المحاولة.'
                      : 'The selected role is unavailable. Refresh and try again.';
                });
                return;
              }

              final role = matchingRoles.first;
              final model = UserModel(
                id: user?.id ?? const Uuid().v4(),
                username: usernameController.text.trim(),
                fullName: fullNameController.text.trim(),
                email: emailController.text.trim(),
                phone: phoneController.text.trim(),
                roleId: role.id,
                roleName: role.name,
                jobTitle: jobTitleController.text.trim(),
                passwordHash: '',
                avatarBase64: avatarBase64,
                cloudAuthUid: user?.cloudAuthUid,
                authProvider: user?.authProvider ?? 'supabase',
                cloudEmailVerified: user?.cloudEmailVerified ?? false,
                isActive: isActive,
                createdAt: user?.createdAt ?? DateTime.now(),
                lastLoginAt: user?.lastLoginAt,
                updatedAt: user == null ? null : DateTime.now(),
              );

              setDialogState(() {
                submitting = true;
                submitError = null;
              });
              try {
                if (user == null) {
                  await controller.addUser(
                    model,
                    password: passwordController.text,
                  );
                } else {
                  await controller.updateUser(model);
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (!context.mounted) return;
                setDialogState(() {
                  submitting = false;
                  submitError = userFacingError(
                    error,
                    isArabic: context.l10n.isArabic,
                  );
                });
              }
            }

            return AlertDialog(
              title: AppText(
                user == null
                    ? context.l10n.text('addUser')
                    : context.l10n.text('editUser'),
              ),
              content: SizedBox(
                width: AppResponsive.dialogWidth(context, 650),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        securedField(
                          'avatar',
                          CircleAvatar(
                            radius: 48,
                            backgroundImage: avatarBytes == null
                                ? null
                                : MemoryImage(avatarBytes),
                            child: avatarBytes == null
                                ? const Icon(Icons.person_outline, size: 44)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            securedField(
                              'avatar',
                              OutlinedButton.icon(
                                onPressed: submitting ? null : chooseAvatar,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: AppText(
                                  context.l10n.text('choosePhoto'),
                                ),
                              ),
                            ),
                            if (avatarBase64 != null)
                              securedField(
                                'avatar',
                                TextButton.icon(
                                  onPressed: submitting
                                      ? null
                                      : () {
                                          setDialogState(
                                            () => avatarBase64 = null,
                                          );
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                  label: AppText(
                                    context.l10n.text('removePhoto'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        securedField(
                          'fullName',
                          TextFormField(
                            controller: fullNameController,
                            decoration: InputDecoration(
                              labelText: context.l10n.text('fullName'),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? context.l10n.text('nameRequired')
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        securedField(
                          'username',
                          TextFormField(
                            controller: usernameController,
                            decoration: InputDecoration(
                              labelText: context.l10n.text('username'),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().length < 3
                                ? context.l10n.text('minimum3')
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (user == null) ...[
                          securedField(
                            'password',
                            TextFormField(
                              controller: passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: context.l10n.text('password'),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  value == null || value.length < 8
                                  ? (context.l10n.isArabic
                                        ? 'كلمة المرور يجب ألا تقل عن 8 أحرف.'
                                        : 'Password must be at least 8 characters.')
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: securedField(
                                'email',
                                TextFormField(
                                  controller: emailController,
                                  decoration: InputDecoration(
                                    labelText: context.l10n.text('email'),
                                    border: const OutlineInputBorder(),
                                    helperText: user == null
                                        ? null
                                        : (context.l10n.isArabic
                                              ? 'تغيير البريد يتطلب تحديث حساب Supabase Authentication.'
                                              : 'Changing email requires updating the Supabase Authentication account.'),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  readOnly: user != null,
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    return email.contains('@')
                                        ? null
                                        : (context.l10n.isArabic
                                              ? 'أدخل بريدًا إلكترونيًا صالحًا.'
                                              : 'Enter a valid email address.');
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: securedField(
                                'phone',
                                TextFormField(
                                  controller: phoneController,
                                  decoration: InputDecoration(
                                    labelText: context.l10n.text('phone'),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        securedField(
                          'jobTitle',
                          TextFormField(
                            controller: jobTitleController,
                            decoration: InputDecoration(
                              labelText: context.l10n.isArabic
                                  ? 'الدرجة الوظيفية'
                                  : 'Job title',
                              hintText: context.l10n.isArabic
                                  ? 'مثال: مدير المبيعات'
                                  : 'Example: Sales Director',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        securedField(
                          'roleId',
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: roleId,
                            decoration: InputDecoration(
                              labelText: context.l10n.text('role'),
                              border: const OutlineInputBorder(),
                            ),
                            items: controller.roles
                                .where(
                                  (role) =>
                                      role.id != 'role-admin' ||
                                      controller.canAssignSystemAdmin ||
                                      user?.roleId == 'role-admin',
                                )
                                .map(
                                  (role) => DropdownMenuItem(
                                    value: role.id,
                                    child: AppText(role.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setDialogState(() => roleId = value);
                            },
                            validator: (value) => value == null
                                ? context.l10n.text('chooseRole')
                                : null,
                          ),
                        ),
                        securedField(
                          'isActive',
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: AppText(context.l10n.text('activeAccount')),
                            value: isActive,
                            onChanged: submitting
                                ? null
                                : (value) {
                                    setDialogState(() => isActive = value);
                                  },
                          ),
                        ),
                        if (submitError != null) ...[
                          const SizedBox(height: 8),
                          Material(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: AppText(
                                      submitError!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: AppText(context.l10n.text('cancel')),
                ),
                FilledButton.icon(
                  onPressed: submitting ? null : submitUser,
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: AppText(
                    submitting
                        ? (context.l10n.isArabic ? 'جارٍ الحفظ' : 'Saving')
                        : context.l10n.text('save'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            user == null
                ? (context.l10n.isArabic
                      ? 'تم إنشاء المستخدم وتحديث القائمة.'
                      : 'The user was created and the list was refreshed.')
                : (context.l10n.isArabic
                      ? 'تم تحديث المستخدم.'
                      : 'The user was updated.'),
          ),
        ),
      );
    }

    fullNameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
  }

  Future<void> _customizeUserPermissions(UserModel user) async {
    final controller = context.read<AccessController>();
    final canManage =
        controller.isSystemAdmin ||
        controller.hasPermission(PermissionCodes.permissionScopesManage);
    if (!canManage) {
      await controller.recordDeniedAccess(
        PermissionCodes.permissionScopesManage,
      );
      return;
    }
    final override = await controller.getUserPermissionOverride(user.id);
    final rolePermissions = await controller.getRolePermissions(user.roleId);
    var useCustom = override.enabled;
    var selected = Set<String>.from(
      override.enabled ? override.codes : rolePermissions,
    );
    var lastCustomSelection = Set<String>.from(override.codes);
    var permissionQuery = '';
    if (!mounted) return;
    final saved = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final grouped = <String, List<PermissionModel>>{};
          final visiblePermissions = controller.permissions.where((permission) {
            final query = permissionQuery.trim().toLowerCase();
            if (query.isEmpty) return true;
            return '${permission.name} ${permission.code} ${permission.module} ${permission.description}'
                .toLowerCase()
                .contains(query);
          });
          for (final permission in visiblePermissions) {
            grouped.putIfAbsent(permission.module, () => []).add(permission);
          }
          return AlertDialog(
            title: AppText(
              context.l10n.isArabic
                  ? 'صلاحيات المستخدم: ${user.fullName}'
                  : 'User permissions: ${user.fullName}',
            ),
            content: SizedBox(
              width: AppResponsive.dialogWidth(context, 780),
              height: AppResponsive.dialogHeight(context, 600),
              child: Column(
                children: [
                  Card(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: SwitchListTile(
                      value: useCustom,
                      title: AppText(
                        context.l10n.isArabic
                            ? 'استخدام صلاحيات مخصصة لهذا المستخدم'
                            : 'Use permissions customized for this user',
                      ),
                      subtitle: AppText(
                        useCustom
                            ? (context.l10n.isArabic
                                  ? 'يمكن منح أو سحب كل صلاحية بشكل مستقل، بما في ذلك سحب جميع الصلاحيات.'
                                  : 'Each permission can be granted or revoked independently, including revoking all permissions.')
                            : (context.l10n.isArabic
                                  ? 'المستخدم يرث صلاحيات دوره تلقائيًا.'
                                  : 'The user inherits role permissions automatically.'),
                      ),
                      onChanged: (value) => setState(() {
                        if (useCustom) {
                          lastCustomSelection = Set<String>.from(selected);
                        }
                        useCustom = value;
                        selected = value
                            ? Set<String>.from(lastCustomSelection)
                            : Set<String>.from(rolePermissions);
                      }),
                    ),
                  ),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      labelText: context.l10n.isArabic
                          ? 'البحث في الصلاحيات'
                          : 'Search permissions',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => permissionQuery = value),
                  ),
                  const SizedBox(height: 6),
                  if (useCustom)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() {
                              selected = controller.permissions
                                  .map((permission) => permission.code)
                                  .toSet();
                            }),
                            icon: const Icon(Icons.select_all),
                            label: const AppText('تحديد الكل'),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(selected.clear),
                            icon: const Icon(Icons.deselect),
                            label: const AppText('إلغاء الكل'),
                          ),
                          const Spacer(),
                          AppText('المحدد: ${selected.length}'),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      children: grouped.entries.map((entry) {
                        return ExpansionTile(
                          initiallyExpanded: true,
                          title: AppText(entry.key),
                          children: entry.value.map((permission) {
                            final inherited = rolePermissions.contains(
                              permission.code,
                            );
                            return CheckboxListTile(
                              value: selected.contains(permission.code),
                              enabled: useCustom,
                              title: AppText(permission.name),
                              subtitle: AppText(
                                '${permission.code}${!useCustom && inherited ? ' • موروثة من الدور' : ''}',
                              ),
                              onChanged: useCustom
                                  ? (checked) => setState(() {
                                      if (checked == true) {
                                        selected.add(permission.code);
                                      } else {
                                        selected.remove(permission.code);
                                      }
                                    })
                                  : null,
                            );
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: AppText(context.l10n.isArabic ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: AppText(context.l10n.isArabic ? 'حفظ' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true && mounted) {
      await _runUserMutation(
        () => useCustom
            ? controller.saveUserPermissions(user.id, selected)
            : controller.clearUserPermissionOverride(user.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: AppPillTabBar(
            controller: _tabs,
            tabs: [
              AppPillTab(context.l10n.text('users'), Icons.people_outline),
              AppPillTab(
                context.l10n.text('permissions'),
                Icons.security_outlined,
              ),
              AppPillTab(context.l10n.text('auditLog'), Icons.history),
            ],
          ),
        ),
      ),
      body: Consumer<AccessController>(
        builder: (context, controller, child) {
          return TabBarView(
            controller: _tabs,
            children: [
              _usersTab(controller),
              FieldPermissionVisibility(
                resource: 'users',
                field: 'customPermissions',
                viewPermission: 'users.view',
                child: _PermissionsEditor(controller: controller),
              ),
              FieldPermissionVisibility(
                resource: 'users',
                field: 'auditMetadata',
                viewPermission: 'audit.view',
                child: _logsTab(controller),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _usersTab(AccessController controller) {
    final query = _query.toLowerCase();
    final users = controller.users.where((user) {
      return query.isEmpty ||
          user.fullName.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query) ||
          user.roleName.toLowerCase().contains(query);
    }).toList();

    return RefreshIndicator(
      onRefresh: controller.loadAccess,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: controller.isSystemAdmin
                ? FilledButton.icon(
                    onPressed: () => _editUser(),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: AppText(context.l10n.text('newUser')),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              labelText: context.l10n.isArabic ? 'البحث' : 'Search',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (controller.isLoading && controller.users.isEmpty)
            KajAdminState(
              kind: KajAdminStateKind.loading,
              title: context.l10n.isArabic
                  ? 'جاري تحميل المستخدمين'
                  : 'Loading users',
              message: context.l10n.isArabic
                  ? 'تتم مزامنة المستخدمين والأدوار والصلاحيات.'
                  : 'Synchronizing users, roles and permissions.',
            )
          else if (controller.errorMessage != null && controller.users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 44),
                  const SizedBox(height: 12),
                  AppText(
                    controller.errorMessage!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: controller.loadAccess,
                    icon: const Icon(Icons.refresh),
                    label: AppText(
                      context.l10n.isArabic ? 'إعادة المحاولة' : 'Retry',
                    ),
                  ),
                ],
              ),
            )
          else if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(50),
              child: Center(
                child: AppText(
                  context.l10n.isArabic ? 'لا توجد نتائج.' : 'No results.',
                ),
              ),
            )
          else
            ...users.map(
              (user) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: _ProfileAvatar(user: user),
                  title: AppText(
                    user.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: AppText(
                    '@${user.username} • ${user.roleName}'
                    '${user.email.isEmpty ? '' : ' • ${user.email}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.isSystemAdmin ||
                          controller.hasPermission(
                            PermissionCodes.permissionScopesManage,
                          ))
                        FieldPermissionVisibility(
                          resource: 'users',
                          field: 'customPermissions',
                          viewPermission: 'users.view',
                          child: Tooltip(
                            message: context.l10n.isArabic
                                ? 'تخصيص صلاحيات هذا المستخدم'
                                : 'Customize this user permissions',
                            child: OutlinedButton.icon(
                              key: ValueKey(
                                'custom-user-permissions-${user.id}',
                              ),
                              onPressed: () => _customizeUserPermissions(user),
                              icon: const Icon(
                                Icons.admin_panel_settings_outlined,
                                size: 18,
                              ),
                              label: AppText(
                                context.l10n.isArabic
                                    ? 'صلاحيات مخصصة'
                                    : 'Custom permissions',
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await _editUser(user);
                            return;
                          }
                          if (value == 'permissions') {
                            await _customizeUserPermissions(user);
                            return;
                          }
                          if (value == 'toggle') {
                            await _runUserMutation(
                              () => controller.updateUser(
                                user.copyWith(
                                  isActive: !user.isActive,
                                  updatedAt: DateTime.now(),
                                ),
                              ),
                            );
                            return;
                          }
                          if (value == 'delete') {
                            final confirmed = await showAppConfirmDialog(
                              context,
                              title: context.l10n.text('delete'),
                              message: context.l10n.isArabic
                                  ? 'حذف ${user.fullName}؟'
                                  : 'Delete ${user.fullName}?',
                              confirmLabel: context.l10n.text('delete'),
                              destructive: true,
                            );
                            if (confirmed == true && mounted) {
                              await _runUserMutation(
                                () => controller.deleteUser(user),
                              );
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: AppText(context.l10n.text('edit')),
                          ),
                          if (controller.canViewField(
                            'users',
                            'customPermissions',
                            viewPermission: 'users.view',
                          ))
                            PopupMenuItem(
                              value: 'permissions',
                              child: AppText(
                                context.l10n.isArabic
                                    ? 'تخصيص الصلاحيات'
                                    : 'Customize permissions',
                              ),
                            ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: AppText(
                              user.isActive
                                  ? (context.l10n.isArabic
                                        ? 'إيقاف'
                                        : 'Disable')
                                  : (context.l10n.isArabic
                                        ? 'تفعيل'
                                        : 'Enable'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: AppText(
                              context.l10n.text('delete'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  ExportDocument _auditReport(AccessController controller) {
    final rows = controller.auditLogs;
    return ExportDocument(
      title: 'Audit Log Report',
      subtitle: 'User access and ERP operation audit trail',
      language: 'en',
      generatedAt: DateTime.now(),
      metadata: <String, Object?>{
        'Result count': rows.length,
        'Outcome filter': _auditOutcome,
        'Search': _auditQuery.trim(),
      },
      columns: const <ExportColumn>[
        ExportColumn(
          key: 'time',
          label: 'Date & time',
          type: ExportValueType.dateTime,
          width: 1.25,
        ),
        ExportColumn(key: 'user', label: 'User', width: 1.2),
        ExportColumn(key: 'action', label: 'Action'),
        ExportColumn(key: 'module', label: 'Module'),
        ExportColumn(key: 'entity', label: 'Entity type'),
        ExportColumn(key: 'outcome', label: 'Outcome'),
        ExportColumn(key: 'source', label: 'Source'),
        ExportColumn(key: 'description', label: 'Description', width: 2.1),
      ],
      rows: rows
          .map<List<Object?>>(
            (log) => <Object?>[
              log.createdAt.toLocal(),
              log.userName,
              log.action,
              log.module,
              log.entityType,
              log.outcome,
              log.source,
              log.description,
            ],
          )
          .toList(growable: false),
    );
  }

  Future<void> _exportAuditPdf(AccessController controller) async {
    if (controller.auditLogs.isEmpty) return;
    try {
      await PdfExportService().preview(
        _auditReport(controller),
        pageFormat: ExportPageFormat.a4Landscape,
      );
      await controller.recordAuditEvent(
        action: 'export',
        module: 'audit',
        description: 'Exported audit log report as PDF',
        entityType: 'audit_report',
        metadata: <String, Object?>{
          'format': 'pdf',
          'rowCount': controller.auditLogs.length,
          'query': _auditQuery.trim(),
          'outcomeFilter': _auditOutcome,
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _exportAuditExcel(AccessController controller) async {
    if (controller.auditLogs.isEmpty) return;
    try {
      await ExcelExportService().save(_auditReport(controller));
      await controller.recordAuditEvent(
        action: 'export',
        module: 'audit',
        description: 'Exported audit log report as Excel',
        entityType: 'audit_report',
        metadata: <String, Object?>{
          'format': 'xlsx',
          'rowCount': controller.auditLogs.length,
          'query': _auditQuery.trim(),
          'outcomeFilter': _auditOutcome,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'تم إنشاء تقرير سجل التدقيق بصيغة Excel.'
                : 'Audit log Excel report created.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _logsTab(AccessController controller) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 420,
              child: TextField(
                onChanged: (value) async {
                  _auditQuery = value;
                  await controller.searchAuditLogs(
                    _auditQuery,
                    outcome: _auditOutcome,
                  );
                },
                decoration: InputDecoration(
                  labelText: context.l10n.isArabic
                      ? 'البحث بالمستخدم أو الوحدة أو السجل'
                      : 'Search user, module, or record',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            DropdownButton<String>(
              value: _auditOutcome,
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: AppText(
                    context.l10n.isArabic ? 'كل النتائج' : 'All outcomes',
                  ),
                ),
                DropdownMenuItem(
                  value: 'success',
                  child: AppText(context.l10n.isArabic ? 'ناجحة' : 'Success'),
                ),
                DropdownMenuItem(
                  value: 'denied',
                  child: AppText(context.l10n.isArabic ? 'مرفوضة' : 'Denied'),
                ),
                DropdownMenuItem(
                  value: 'failure',
                  child: AppText(context.l10n.isArabic ? 'فاشلة' : 'Failed'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _auditOutcome = value);
                await controller.searchAuditLogs(
                  _auditQuery,
                  outcome: _auditOutcome,
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: controller.auditLogs.isEmpty
                  ? null
                  : () => _exportAuditPdf(controller),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: AppText(
                context.l10n.isArabic ? 'تصدير PDF' : 'Export PDF',
              ),
            ),
            OutlinedButton.icon(
              onPressed: controller.auditLogs.isEmpty
                  ? null
                  : () => _exportAuditExcel(controller),
              icon: const Icon(Icons.table_view_outlined),
              label: AppText(
                context.l10n.isArabic ? 'تصدير Excel' : 'Export Excel',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (controller.auditLogs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(50),
            child: Center(
              child: AppText(
                context.l10n.isArabic
                    ? 'لا توجد عمليات مسجلة.'
                    : 'No audit entries.',
              ),
            ),
          )
        else
          ...controller.auditLogs.map(
            (log) => Card(
              child: ListTile(
                onTap: () => _showAuditDetails(log),
                leading: Icon(
                  log.isDenied
                      ? Icons.gpp_bad_outlined
                      : log.isFailure
                      ? Icons.error_outline
                      : Icons.history,
                  color: log.isDenied || log.isFailure ? Colors.red : null,
                ),
                title: AppText(log.description),
                subtitle: AppText(
                  '${log.userName} • ${log.module} • '
                  '${log.createdAt.toLocal().toString().split('.').first}',
                ),
                trailing: AppText(log.outcome),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showAuditDetails(AuditLogModel log) async {
    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          context.l10n.isArabic ? 'تفاصيل سجل العملية' : 'Audit details',
        ),
        content: AppSelectableText(
          [
            '${context.l10n.isArabic ? 'المستخدم' : 'User'}: ${log.userName}',
            '${context.l10n.isArabic ? 'العملية' : 'Action'}: ${log.action}',
            '${context.l10n.isArabic ? 'النتيجة' : 'Outcome'}: ${log.outcome}',
            '${context.l10n.isArabic ? 'الوحدة' : 'Module'}: ${log.module}',
            '${context.l10n.isArabic ? 'نوع العملية' : 'Operation type'}: ${log.entityType}',
            '${context.l10n.isArabic ? 'المصدر' : 'Source'}: ${log.source}',
            '${context.l10n.isArabic ? 'الوقت' : 'Time'}: ${log.createdAt.toLocal()}',
            '',
            log.description,
            if (log.metadataJson?.trim().isNotEmpty == true) ...<String>[
              '',
              '${context.l10n.isArabic ? 'تفاصيل التغيير' : 'Change details'}:',
              log.metadataJson!.trim(),
            ],
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: AppText(context.l10n.isArabic ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  Uint8List? _decodeAvatar(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final normalized = value.contains(',') && value.startsWith('data:image/')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      final bytes = AppImageService.decodeBase64(normalized);
      return bytes == null || bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (user.avatarBase64 != null && user.avatarBase64!.isNotEmpty) {
      try {
        bytes = base64Decode(user.avatarBase64!);
      } catch (_) {
        bytes = null;
      }
    }

    return CircleAvatar(
      backgroundColor: user.isActive
          ? Theme.of(context).colorScheme.primary
          : Colors.grey,
      backgroundImage: bytes == null ? null : MemoryImage(bytes),
      child: bytes == null
          ? AppText(
              user.fullName.isEmpty ? '?' : user.fullName.substring(0, 1),
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            )
          : null,
    );
  }
}

class _PermissionsEditor extends StatefulWidget {
  const _PermissionsEditor({required this.controller});

  final AccessController controller;

  @override
  State<_PermissionsEditor> createState() => _PermissionsEditorState();
}

class _PermissionsEditorState extends State<_PermissionsEditor> {
  String? roleId;
  Set<String> selected = {};
  bool loading = false;

  Future<void> _loadRole(String id) async {
    setState(() {
      roleId = id;
      loading = true;
    });

    final values = await widget.controller.getRolePermissions(id);

    if (!mounted) {
      return;
    }

    setState(() {
      selected = values;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PermissionModel>>{};
    for (final permission in widget.controller.permissions) {
      grouped.putIfAbsent(permission.module, () => []).add(permission);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: roleId,
          decoration: InputDecoration(
            labelText: context.l10n.text('chooseRole'),
            border: const OutlineInputBorder(),
          ),
          items: widget.controller.roles
              .map(
                (role) =>
                    DropdownMenuItem(value: role.id, child: AppText(role.name)),
              )
              .toList(),
          onChanged: (value) async {
            if (value != null) {
              await _loadRole(value);
            }
          },
        ),
        const SizedBox(height: 16),
        if (loading)
          KajAdminState(
            kind: KajAdminStateKind.loading,
            title: context.l10n.isArabic
                ? 'جاري تحميل المستخدمين'
                : 'Loading users',
            message: context.l10n.isArabic
                ? 'تتم مزامنة المستخدمين والأدوار والصلاحيات.'
                : 'Synchronizing users, roles and permissions.',
          )
        else if (roleId == null)
          Padding(
            padding: const EdgeInsets.all(50),
            child: Center(
              child: AppText(
                context.l10n.isArabic ? 'اختر دورًا.' : 'Choose a role.',
              ),
            ),
          )
        else ...[
          ...grouped.entries.map(
            (entry) => Card(
              child: ExpansionTile(
                initiallyExpanded: true,
                title: AppText(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children: entry.value
                    .map(
                      (permission) => CheckboxListTile(
                        title: AppText(permission.name),
                        subtitle: permission.description.isEmpty
                            ? null
                            : AppText(permission.description),
                        value: selected.contains(permission.code),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selected.add(permission.code);
                            } else {
                              selected.remove(permission.code);
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              await widget.controller.saveRolePermissions(roleId!, selected);

              if (!mounted) {
                return;
              }
            },
            icon: const Icon(Icons.save),
            label: AppText(
              context.l10n.isArabic ? 'حفظ الصلاحيات' : 'Save permissions',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ],
    );
  }
}
