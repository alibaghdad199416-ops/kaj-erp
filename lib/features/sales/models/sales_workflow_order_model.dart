import 'package:quality_line_erp/core/models/model_value_reader.dart';

class SalesWorkflowOrder {
  final String id;
  final String orderNumber;
  final String customerId;
  final String customerName;
  final String status;
  final String currency;
  final double exchangeRate;
  final double subtotal;
  final double discount;
  final double total;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? deliveryId;
  final String? deliveryStatus;
  final String? invoiceId;
  final String? invoiceStatus;
  final double? invoiceRemaining;
  final String? createdBy;
  final String? createdByName;
  final String? carId;
  final String? carName;

  SalesWorkflowOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.status,
    required this.currency,
    required this.exchangeRate,
    required this.subtotal,
    required this.discount,
    required this.total,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.deliveryId,
    this.deliveryStatus,
    this.invoiceId,
    this.invoiceStatus,
    this.invoiceRemaining,
    this.createdBy,
    this.createdByName,
    this.carId,
    this.carName,
  });

  factory SalesWorkflowOrder.fromMap(Map<String, dynamic> map) => SalesWorkflowOrder(
    id: map['id']?.toString() ?? '',
    orderNumber: map['orderNumber']?.toString() ?? '',
    customerId: map['customerId']?.toString() ?? '',
    customerName: map['customerName']?.toString() ?? '',
    status: map['status']?.toString() ?? '',
    currency: map['currency']?.toString() ?? '',
    exchangeRate: ModelValueReader.decimal(map, 'exchangeRate', fallback: 1).toDouble(),
    subtotal: ModelValueReader.decimal(map, 'subtotal', fallback: 0).toDouble(),
    discount: ModelValueReader.decimal(map, 'discount', fallback: 0).toDouble(),
    total: ModelValueReader.decimal(map, 'total', fallback: 0).toDouble(),
    notes: map['notes']?.toString(),
    createdAt: map['createdAt'] != null
        ? DateTime.tryParse(map['createdAt'].toString())
        : null,
    updatedAt: map['updatedAt'] != null
        ? DateTime.tryParse(map['updatedAt'].toString())
        : null,
    deliveryId: map['deliveryId']?.toString(),
    deliveryStatus: map['deliveryStatus']?.toString(),
    invoiceId: map['invoiceId']?.toString(),
    invoiceStatus: map['invoiceStatus']?.toString(),
    invoiceRemaining: map['invoiceRemaining'] != null
        ? ModelValueReader.decimal(map, 'invoiceRemaining').toDouble()
        : null,
    createdBy: map['createdBy']?.toString(),
    createdByName: map['createdByName']?.toString(),
    carId: map['carId']?.toString(),
    carName: map['carName']?.toString(),
  );
}