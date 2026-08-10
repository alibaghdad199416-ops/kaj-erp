import 'package:quality_line_erp/core/models/model_value_reader.dart';

class CashAccountModel {
  const CashAccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.openingBalance,
    required this.isActive,
    required this.accountId,
    required this.createdAt,
    this.updatedAt,
    this.linkedCashAccountId,
  });

  final String id;
  final String name;
  final String type;
  final String currency;
  final double openingBalance;
  final bool isActive;
  final String accountId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? linkedCashAccountId;

  void validate() {
    if (id.trim().isEmpty) throw ArgumentError('مرجع الصندوق مطلوب');
    if (name.trim().isEmpty) throw ArgumentError('اسم الصندوق مطلوب');
    if (accountId.trim().isEmpty) throw ArgumentError('الحساب المحاسبي مطلوب');
    if (openingBalance < 0) throw ArgumentError('الرصيد الافتتاحي غير صحيح');
    if (currency != 'USD' && currency != 'IQD') {
      throw ArgumentError('عملة الصندوق غير مدعومة');
    }
  }

  CashAccountModel copyWith({
    String? id,
    String? name,
    String? type,
    String? currency,
    double? openingBalance,
    bool? isActive,
    String? accountId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? linkedCashAccountId,
  }) => CashAccountModel(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    openingBalance: openingBalance ?? this.openingBalance,
    isActive: isActive ?? this.isActive,
    accountId: accountId ?? this.accountId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    linkedCashAccountId: linkedCashAccountId ?? this.linkedCashAccountId,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'currency': currency,
    'openingBalance': openingBalance,
    'isActive': isActive ? 1 : 0,
    'accountId': accountId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'linkedCashAccountId': linkedCashAccountId,
  };

  Map<String, dynamic> toCloudMap() => {
    'id': id,
    'name': name,
    'type': type,
    'currency': currency,
    'opening_balance': openingBalance,
    'is_active': isActive,
    'accountId': accountId,
    'account_id': accountId,
    'canonical': accountId,
    'ledgerAccountId': accountId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'linked_cash_account_id': linkedCashAccountId,
    'schema_version': 2,
  };

  factory CashAccountModel.fromMap(Map<String, dynamic> map) =>
      CashAccountModel(
        id: ModelValueReader.string(map, 'id'),
        name: ModelValueReader.string(map, 'name'),
        type: ModelValueReader.string(map, 'type', fallback: 'cash'),
        currency: ModelValueReader.string(map, 'currency').toUpperCase(),
        openingBalance: ModelValueReader.decimal(
          map,
          'openingBalance',
          aliases: const ['opening_balance'],
        ),
        isActive: ModelValueReader.boolean(
          map,
          'isActive',
          aliases: const ['is_active'],
          fallback: false,
        ),
        accountId: ModelValueReader.string(
          map,
          'accountId',
          aliases: const ['account_id'],
        ),
        createdAt: ModelValueReader.requiredDateTime(
          map,
          'createdAt',
          aliases: const ['created_at'],
        ),
        updatedAt: ModelValueReader.dateTime(
          map,
          'updatedAt',
          aliases: const ['updated_at'],
        ),
        linkedCashAccountId: ModelValueReader.string(
          map,
          'linkedCashAccountId',
          aliases: const ['linked_cash_account_id'],
        ),
      );

  factory CashAccountModel.fromCloudMap(Map<String, dynamic> map) {
    final normalized = Map<String, dynamic>.from(map);
    // The snake-case value is authoritative for cloud rows. Older rows may
    // retain a stale camel-case alias after an account reassignment.
    final cloudAccountId =
        (normalized['canonical'] ??
                normalized['account_id'] ??
                normalized['accountId'] ??
                normalized['ledgerAccountId'])
            ?.toString()
            .trim();
    if (cloudAccountId != null && cloudAccountId.isNotEmpty) {
      normalized['accountId'] = cloudAccountId;
      normalized['account_id'] = cloudAccountId;
      normalized['canonical'] = cloudAccountId;
      normalized['ledgerAccountId'] = cloudAccountId;
    }
    final linkedId = normalized['linked_cash_account_id']?.toString().trim();
    if (linkedId != null && linkedId.isNotEmpty) {
      normalized['linkedCashAccountId'] = linkedId;
    }
    // The PostgreSQL row timestamp is the concurrency fallback for legacy
    // cashboxes that predate a data.updatedAt field. Every edit therefore
    // carries a freshness token instead of silently overwriting a newer row.
    final cloudUpdatedAt = normalized['_cloudUpdatedAt']?.toString().trim();
    if (cloudUpdatedAt != null && cloudUpdatedAt.isNotEmpty) {
      // PostgreSQL row.updated_at is the only concurrency token. Never prefer
      // a historical data.updatedAt alias because that can make the next save
      // look stale and silently appear to revert after re-opening the screen.
      normalized['updatedAt'] = cloudUpdatedAt;
      normalized['updated_at'] = cloudUpdatedAt;
    }
    return CashAccountModel.fromMap(normalized);
  }

  @override
  bool operator ==(Object other) => other is CashAccountModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
