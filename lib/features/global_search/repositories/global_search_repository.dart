import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/global_search/models/global_search_result.dart';

class GlobalSearchRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.'));

  Future<List<GlobalSearchResult>> search(
    String query, {
    int limit = 50,
  }) async {
    final text = query.trim();
    if (text.length < 2) return const [];
    final rows = await _client.rpc(
      'erp_r49_cloud_global_search',
      params: {
        'p_company_id': _companyId,
        'p_query': text,
        'p_limit': limit.clamp(1, 200),
      },
    );
    final values = rows is List
        ? rows
        : rows is Map && rows['results'] is List
        ? rows['results'] as List
        : const <Object?>[];
    return values
        .whereType<Map>()
        .map((e) {
          final m = Map<String, Object?>.from(e);
          return GlobalSearchResult(
            id: m['id']?.toString() ?? '',
            type: m['type']?.toString() ?? '',
            title: m['title']?.toString() ?? '',
            subtitle: m['subtitle']?.toString() ?? '',
            route: m['route']?.toString() ?? '/',
            permission: m['permission']?.toString() ?? '',
            icon: _icon(m['icon']?.toString()),
            status: m['status']?.toString(),
            amount: _number(m['amount']),
            currency: _currency(m['currency']),
            date: m['date']?.toString(),
          );
        })
        .toList(growable: false);
  }

  static String? _currency(Object? value) {
    final code = value?.toString().trim().toUpperCase() ?? '';
    return code == 'USD' || code == 'IQD' ? code : null;
  }

  static double? _number(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static IconData _icon(String? value) => switch (value) {
    'car' => Icons.directions_car_outlined,
    'inventory' => Icons.inventory_2_outlined,
    'customer' => Icons.person_outline,
    'supplier' => Icons.local_shipping_outlined,
    'opportunity' => Icons.handshake_outlined,
    'sale' => Icons.receipt_long_outlined,
    'purchase' => Icons.shopping_cart_outlined,
    'account' => Icons.account_balance_outlined,
    'journal' => Icons.menu_book_outlined,
    'document' => Icons.description_outlined,
    _ => Icons.search,
  };
}
