import 'package:quality_line_erp/core/models/model_value_reader.dart';
import 'package:quality_line_erp/core/utils/business_date_codec.dart';

class InstallmentModel {
  final String id;
  final String saleId;
  final int installmentNo;
  final DateTime dueDate;
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final String status;
  final String currencyCode;
  final DateTime? paymentDate;
  final String notes;

  const InstallmentModel({
    required this.id,
    required this.saleId,
    required this.installmentNo,
    required this.dueDate,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    this.currencyCode = 'USD',
    this.paymentDate,
    this.notes = '',
  });

  factory InstallmentModel.fromMap(Map<String, dynamic> map) {
    return InstallmentModel(
      id: ModelValueReader.string(map, 'id'),
      saleId: ModelValueReader.string(map, 'saleId'),
      installmentNo: ModelValueReader.integer(map, 'installmentNo'),
      dueDate: ModelValueReader.requiredDateTime(
        map,
        'dueDate',
        aliases: const [
          'effectiveAt',
          'createdAt',
          'updatedAt',
          '_cloudUpdatedAt',
        ],
      ),
      amount: ModelValueReader.decimal(map, 'amount'),
      paidAmount: ModelValueReader.decimal(map, 'paidAmount'),
      remainingAmount: ModelValueReader.decimal(map, 'remainingAmount'),
      status: ModelValueReader.string(map, 'status'),
      currencyCode: ModelValueReader.string(map, 'currencyCode').toUpperCase(),
      paymentDate: ModelValueReader.dateTime(map, 'paymentDate'),
      notes: ModelValueReader.string(map, 'notes'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'saleId': saleId,
      'installmentNo': installmentNo,
      'dueDate': BusinessDateCodec.encode(dueDate),
      'amount': amount,
      'paidAmount': paidAmount,
      'remainingAmount': remainingAmount,
      'status': status,
      'currencyCode': currencyCode,
      'paymentDate': paymentDate?.toIso8601String(),
      'notes': notes,
    };
  }

  Map<String, dynamic> toCloudMap() => {
    'id': id,
    'saleId': saleId,
    'installmentNo': installmentNo,
    'dueDate': BusinessDateCodec.encode(dueDate),
    'amount': amount,
    'paidAmount': paidAmount,
    'remainingAmount': remainingAmount,
    'status': status,
    'paymentDate': paymentDate?.toUtc().toIso8601String(),
    'notes': notes,
  };

  InstallmentModel copyWith({
    String? id,
    String? saleId,
    int? installmentNo,
    DateTime? dueDate,
    double? amount,
    double? paidAmount,
    double? remainingAmount,
    String? status,
    String? currencyCode,
    DateTime? paymentDate,
    String? notes,
  }) {
    return InstallmentModel(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      installmentNo: installmentNo ?? this.installmentNo,
      dueDate: dueDate ?? this.dueDate,
      amount: amount ?? this.amount,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      status: status ?? this.status,
      currencyCode: currencyCode ?? this.currencyCode,
      paymentDate: paymentDate ?? this.paymentDate,
      notes: notes ?? this.notes,
    );
  }
}
