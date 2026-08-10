import 'package:quality_line_erp/core/models/model_value_reader.dart';

class CarImageModel {
  const CarImageModel({
    required this.id,
    required this.carId,
    required this.imageBase64,
    required this.sortOrder,
    required this.createdAt,
    this.thumbnailBase64 = '',
  });

  final String id;
  final String carId;
  final String imageBase64;
  final String thumbnailBase64;
  final int sortOrder;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'carId': carId,
    'imageBase64': imageBase64,
    'thumbnailBase64': thumbnailBase64,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CarImageModel.fromMap(Map<String, dynamic> map) => CarImageModel(
    id: ModelValueReader.string(map, 'id'),
    carId: ModelValueReader.string(map, 'carId'),
    imageBase64: ModelValueReader.string(map, 'imageBase64'),
    thumbnailBase64: ModelValueReader.string(
      map,
      'thumbnailBase64',
      aliases: const ['thumbnail_base64'],
    ),
    sortOrder: ModelValueReader.integer(map, 'sortOrder'),
    createdAt: ModelValueReader.requiredDateTime(
      map,
      'createdAt',
      aliases: const ['updatedAt', '_cloudUpdatedAt'],
    ),
  );
}
