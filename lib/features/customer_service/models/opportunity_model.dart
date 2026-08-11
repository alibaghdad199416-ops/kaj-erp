import 'package:quality_line_erp/core/models/model_value_reader.dart';

enum OpportunityStatus { pending, won, lost }

class OpportunityModel {
  const OpportunityModel({
    required this.id,
    required this.opportunityNumber,
    this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.title,
    required this.source,
    required this.expectedValue,
    this.currency = 'USD',
    this.stage = 'new',
    this.probability = 0,
    this.description,
    this.expectedCloseDate,
    this.winLossReason,
    required this.status,
    this.carId,
    this.carName,
    this.saleId,
    this.invoiceNumber,
    this.salesOrderStatus,
    this.deliveryNumber,
    this.deliveryStatus,
    this.invoiceStatus,
    this.paymentStatus,
    this.paidAmount = 0,
    this.remainingAmount = 0,
    required this.assignedUserId,
    required this.assignedUserName,
    required this.createdByUserId,
    required this.createdByUserName,
    required this.createdAt,
    this.followUpDate,
    this.closedAt,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String opportunityNumber;
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final String title;
  final String source;
  final double expectedValue;
  final String currency;
  final String stage;
  final double probability;
  final String? description;
  final DateTime? expectedCloseDate;
  final String? winLossReason;
  final OpportunityStatus status;
  final String? carId;
  final String? carName;
  final String? saleId;
  final String? invoiceNumber;
  final String? salesOrderStatus;
  final String? deliveryNumber;
  final String? deliveryStatus;
  final String? invoiceStatus;
  final String? paymentStatus;
  final double paidAmount;
  final double remainingAmount;
  final String assignedUserId;
  final String assignedUserName;
  final String createdByUserId;
  final String createdByUserName;
  final DateTime createdAt;
  final DateTime? followUpDate;
  final DateTime? closedAt;
  final String? notes;
  final DateTime? updatedAt;

  String get statusValue => status.name;

  OpportunityModel copyWith({
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? title,
    String? source,
    double? expectedValue,
    String? currency,
    String? stage,
    double? probability,
    String? description,
    DateTime? expectedCloseDate,
    String? winLossReason,
    OpportunityStatus? status,
    String? carId,
    String? carName,
    String? saleId,
    String? invoiceNumber,
    String? salesOrderStatus,
    String? deliveryNumber,
    String? deliveryStatus,
    String? invoiceStatus,
    String? paymentStatus,
    double? paidAmount,
    double? remainingAmount,
    String? assignedUserId,
    String? assignedUserName,
    DateTime? followUpDate,
    DateTime? closedAt,
    String? notes,
    DateTime? updatedAt,
  }) => OpportunityModel(
    id: id,
    opportunityNumber: opportunityNumber,
    customerId: customerId ?? this.customerId,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    title: title ?? this.title,
    source: source ?? this.source,
    expectedValue: expectedValue ?? this.expectedValue,
    currency: currency ?? this.currency,
    stage: stage ?? this.stage,
    probability: probability ?? this.probability,
    description: description ?? this.description,
    expectedCloseDate: expectedCloseDate ?? this.expectedCloseDate,
    winLossReason: winLossReason ?? this.winLossReason,
    status: status ?? this.status,
    carId: carId ?? this.carId,
    carName: carName ?? this.carName,
    saleId: saleId ?? this.saleId,
    invoiceNumber: invoiceNumber ?? this.invoiceNumber,
    salesOrderStatus: salesOrderStatus ?? this.salesOrderStatus,
    deliveryNumber: deliveryNumber ?? this.deliveryNumber,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    invoiceStatus: invoiceStatus ?? this.invoiceStatus,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    paidAmount: paidAmount ?? this.paidAmount,
    remainingAmount: remainingAmount ?? this.remainingAmount,
    assignedUserId: assignedUserId ?? this.assignedUserId,
    assignedUserName: assignedUserName ?? this.assignedUserName,
    createdByUserId: createdByUserId,
    createdByUserName: createdByUserName,
    createdAt: createdAt,
    followUpDate: followUpDate ?? this.followUpDate,
    closedAt: closedAt ?? this.closedAt,
    notes: notes ?? this.notes,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'opportunityNumber': opportunityNumber,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'title': title,
    'source': source,
    'expectedValue': expectedValue,
    'currency': currency,
    'stage': stage,
    'probability': probability,
    'description': description,
    'expectedCloseDate': expectedCloseDate?.toIso8601String(),
    'winLossReason': winLossReason,
    'status': status.name,
    'carId': carId,
    'carName': carName,
    'saleId': saleId,
    'invoiceNumber': invoiceNumber,
    'salesOrderStatus': salesOrderStatus,
    'deliveryNumber': deliveryNumber,
    'deliveryStatus': deliveryStatus,
    'invoiceStatus': invoiceStatus,
    'paymentStatus': paymentStatus,
    'paidAmount': paidAmount,
    'remainingAmount': remainingAmount,
    'assignedUserId': assignedUserId,
    'assignedUserName': assignedUserName,
    'createdByUserId': createdByUserId,
    'createdByUserName': createdByUserName,
    'createdAt': createdAt.toIso8601String(),
    'followUpDate': followUpDate?.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
    'notes': notes,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory OpportunityModel.fromMap(Map<String, dynamic> map) {
    String text(Object? value, {String fallback = ''}) {
      final result = value?.toString().trim() ?? '';
      return result.isEmpty ? fallback : result;
    }

    Object? value(String key, {List<String> aliases = const []}) =>
        ModelValueReader.raw(map, key, aliases: aliases);

    String? nullableText(Object? value) {
      final result = value?.toString().trim() ?? '';
      return result.isEmpty ? null : result;
    }

    double number(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    DateTime? date(Object? value) =>
        value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
    DateTime requiredDate(Map<String, dynamic> values, List<String> keys) {
      for (final key in keys) {
        final value = date(values[key]);
        if (value != null) return value;
      }
      throw const FormatException(
        'Missing or invalid required timestamp: opportunity.createdAt',
      );
    }

    final rawStatus = text(value('status')).toLowerCase();
    return OpportunityModel(
      id: text(value('id')),
      opportunityNumber: text(value('opportunityNumber'), fallback: '-'),
      customerId: nullableText(value('customerId')),
      customerName: text(value('customerName')),
      customerPhone: text(value('customerPhone')),
      title: text(value('title')),
      source: text(value('source')),
      expectedValue: number(value('expectedValue')),
      currency: text(
        value('currency', aliases: const ['currencyCode']),
      ).toUpperCase(),
      stage: text(value('stage'), fallback: 'new').toLowerCase(),
      probability: number(value('probability')).clamp(0, 100).toDouble(),
      description: nullableText(value('description')),
      expectedCloseDate: date(value('expectedCloseDate')),
      winLossReason: nullableText(value('winLossReason')),
      status: OpportunityStatus.values.firstWhere(
        (value) => value.name == rawStatus,
        orElse: () => OpportunityStatus.pending,
      ),
      carId: nullableText(value('carId')),
      carName: nullableText(value('carName')),
      saleId: nullableText(value('salesOrderId', aliases: const ['saleId'])),
      invoiceNumber: nullableText(value('invoiceNumber')),
      salesOrderStatus: nullableText(value('salesOrderStatus')),
      deliveryNumber: nullableText(value('deliveryNumber')),
      deliveryStatus: nullableText(value('deliveryStatus')),
      invoiceStatus: nullableText(value('invoiceStatus')),
      paymentStatus: nullableText(value('paymentStatus')),
      paidAmount: number(value('paidAmount')),
      remainingAmount: number(value('remainingAmount')),
      assignedUserId: text(value('assignedUserId')),
      assignedUserName: text(value('assignedUserName')),
      createdByUserId: text(value('createdByUserId')),
      createdByUserName: text(value('createdByUserName')),
      createdAt: requiredDate(map, const [
        'createdAt',
        'created_at',
        'updatedAt',
        'updated_at',
        '_cloudUpdatedAt',
        '_cloud_updated_at',
      ]),
      followUpDate: date(value('followUpDate')),
      closedAt: date(value('closedAt')),
      notes: nullableText(value('notes')),
      updatedAt: date(value('updatedAt')),
    );
  }
}
