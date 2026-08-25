import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class CloudCreatedUser {
  const CloudCreatedUser({required this.userId, required this.email});
  final String userId;
  final String email;
}

/// Invokes trusted Edge Functions for the complete cloud user lifecycle. The
/// service-role key remains inside Supabase and never reaches the Flutter app.
class SupabaseUserAdministrationService {
  SupabaseUserAdministrationService._();
  static final instance = SupabaseUserAdministrationService._();

  Future<CloudCreatedUser> createUser({
    required String email,
    required String password,
    required String fullName,
    required String localUserId,
    required String roleCode,
    required Map<String, dynamic> erpUserPayload,
  }) async {
    final normalizedEmail = _validatedEmail(email);
    if (password.length < 8) {
      throw ArgumentError('كلمة المرور يجب ألا تقل عن 8 أحرف.');
    }

    final data = await _invoke(
      functionName: 'admin-create-user',
      body: <String, dynamic>{
        'email': normalizedEmail,
        'password': password,
        'full_name': fullName.trim(),
        'local_user_id': localUserId,
        'role_code': roleCode,
        'erp_user': erpUserPayload,
      },
    );
    final userId = data['user_id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw StateError('لم تُرجع خدمة إنشاء المستخدم معرفًا صالحًا.');
    }
    return CloudCreatedUser(userId: userId, email: normalizedEmail);
  }

  Future<void> updateUser({
    required String cloudUserId,
    required String localUserId,
    required String email,
    required String fullName,
    required String roleCode,
    required bool isActive,
    required Map<String, dynamic> erpUserPayload,
  }) async {
    await _invoke(
      functionName: 'admin-manage-user',
      body: <String, dynamic>{
        'action': 'update',
        'target_user_id': cloudUserId,
        'local_user_id': localUserId,
        'email': _validatedEmail(email),
        'full_name': fullName.trim(),
        'role_code': roleCode,
        'is_active': isActive,
        'erp_user': erpUserPayload,
      },
    );
  }

  Future<void> deleteUser({
    required String cloudUserId,
    required String localUserId,
  }) async {
    await _invoke(
      functionName: 'admin-manage-user',
      body: <String, dynamic>{
        'action': 'delete',
        'target_user_id': cloudUserId,
        'local_user_id': localUserId,
      },
    );
  }

  String _validatedEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (!normalized.contains('@')) {
      throw ArgumentError('يجب إدخال بريد إلكتروني صالح للمستخدم.');
    }
    return normalized;
  }

  Future<Map<String, dynamic>> _invoke({
    required String functionName,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke(functionName, body: body)
          .timeout(const Duration(seconds: 35));
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status < 200 ||
          response.status >= 300 ||
          data['ok'] != true) {
        throw StateError(_messageFor(data['error']?.toString()));
      }
      return data;
    } on FunctionException catch (error) {
      throw StateError(_messageFor(_functionErrorCode(error)));
    } on TimeoutException {
      throw StateError(
        'انتهت مهلة خدمة المستخدمين. تحقق من الاتصال وأعد المحاولة.',
      );
    }
  }

  String? _functionErrorCode(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      return details['error']?.toString();
    }
    if (details is String && details.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map) return decoded['error']?.toString();
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  String _messageFor(String? code) {
    return switch (code) {
      'unauthenticated' => 'انتهت الجلسة السحابية. سجّل الدخول مجددًا.',
      'permission_denied' => 'ليست لديك صلاحية إدارة هذا المستخدم.',
      'membership_not_found' => 'لا توجد عضوية سحابية فعالة للحساب الحالي.',
      'target_membership_not_found' => 'عضوية المستخدم السحابية غير موجودة.',
      'target_identity_mismatch' =>
        'هوية المستخدم المحلية لا تطابق العضوية السحابية.',
      'erp_user_id_mismatch' => 'معرف المستخدم داخل السجل لا يطابق الطلب.',
      'cannot_modify_current_user' =>
        'لا يمكن حذف حسابك الحالي أو تعطيله أو تغيير دوره من هذه الشاشة.',
      'email_already_exists' => 'البريد الإلكتروني مستخدم في حساب سحابي آخر.',
      'user_delete_blocked' =>
        'تعذر حذف حساب Supabase بسبب مراجع قديمة مرتبطة به. طُبّق إصلاح قاعدة البيانات؛ أعد المحاولة.',
      'role_mapping_mismatch' => 'الدور المحلي لا يطابق الدور السحابي.',
      'invalid_input' => 'بيانات المستخدم المرسلة إلى الخدمة غير صالحة.',
      'method_not_allowed' => 'طريقة طلب خدمة المستخدمين غير مسموحة.',
      'server_configuration_missing' =>
        'إعداد خدمة المستخدمين السحابية غير مكتمل.',
      'company_slug_missing' => 'إعداد الشركة السحابية غير مكتمل.',
      'request_failed' =>
        'تعذر إكمال إدارة المستخدم السحابي بسبب خطأ في الخدمة.',
      _ => 'تعذر إكمال إدارة المستخدم السحابي.',
    };
  }
}
