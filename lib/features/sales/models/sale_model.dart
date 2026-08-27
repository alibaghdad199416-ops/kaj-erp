import 'package:quality_line_erp/core/models/model_value_reader.dart';

class SaleModel {
  final String id;
  final String carId;
  final String customerId;
  final double salePrice;
  final double paidAmount;
  final double remainingAmount;
  final String paymentMethod;
  final String saleDate;
  final String notes;
  final String invoiceNumber;
  final String? opportunityId;
  final String? createdByUserId;
  final String? createdByUserName;
  final DateTime? updatedAt;
  final String saleType;
  final String? previousSaleId;
  final String? sellerCustomerId;
  final int saleSequence;
  final String currencyCode;
  final double exchangeRate;

  const SaleModel({
    required this.id,
    required this.carId,
    required this.customerId,
    required this.salePrice,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentMethod,
    required this.saleDate,
    required this.notes,
    String? invoiceNumber,
    this.opportunityId,
    this.createdByUserId,
    this.createdByUserName,
    this.updatedAt,
    this.saleType = 'primary',
    this.previousSaleId,
    this.sellerCustomerId,
    this.saleSequence = 1,
    this.currencyCode = 'USD',
    this.exchangeRate = 1,
  }) : invoiceNumber = invoiceNumber ?? '';

  bool get isResale => saleType == 'resale';
  double get total => salePrice;

  Map<String, dynamic> toMap() => {
    'id': id,
    'carId': carId,
    'customerId': customerId,
    'salePrice': salePrice,
    'paidAmount': paidAmount,
    'remainingAmount': remainingAmount,
    'paymentMethod': paymentMethod,
    'saleDate': saleDate,
    'notes': notes,
    'invoiceNumber': invoiceNumber.isEmpty ? null : invoiceNumber,
    'opportunityId': opportunityId,
    'createdByUserId': createdByUserId,
    'createdByUserName': createdByUserName,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'saleType': saleType,
    'previousSaleId': previousSaleId,
    'sellerCustomerId': sellerCustomerId,
    'saleSequence': saleSequence,
    'currencyCode': currencyCode,
    'exchangeRate': 1,
    'amountUsd': currencyCode == 'USD' ? salePrice : 0,
    'amountIqd': currencyCode == 'IQD' ? salePrice : 0,
  };

  factory SaleModel.fromMap(Map<String, dynamic> map) => SaleModel(
    id: ModelValueReader.string(map, 'id'),
    carId: ModelValueReader.string(map, 'carId'),
    customerId: ModelValueReader.string(map, 'customerId'),
    salePrice: ModelValueReader.decimal(map, 'salePrice'),
    paidAmount: ModelValueReader.decimal(map, 'paidAmount'),
    remainingAmount: ModelValueReader.decimal(map, 'remainingAmount'),
    paymentMethod: ModelValueReader.string(map, 'paymentMethod'),
    saleDate: ModelValueReader.string(map, 'saleDate'),
    notes: ModelValueReader.string(map, 'notes'),
    invoiceNumber: ModelValueReader.nullableString(map, 'invoiceNumber'),
    opportunityId: ModelValueReader.nullableString(map, 'opportunityId'),
    createdByUserId: ModelValueReader.nullableString(map, 'createdByUserId'),
    createdByUserName: ModelValueReader.nullableString(map, 'createdByUserName'),
    updatedAt: ModelValueReader.dateTime(map, 'updatedAt', aliases: const ['_cloudUpdatedAt']),
    saleType: ModelValueReader.string(map, 'saleType', fallback: 'primary'),
    previousSaleId: ModelValueReader.nullableString(map, 'previousSaleId'),
    sellerCustomerId: ModelValueReader.nullableString(map, 'sellerCustomerId'),
    saleSequence: ModelValueReader.integer(map, 'saleSequence', fallback: 1),
    currencyCode: ModelValueReader.string(map, 'currencyCode').toUpperCase(),
    exchangeRate: ModelValueReader.decimal(map, 'exchangeRate', fallback: 1),
  );
}
