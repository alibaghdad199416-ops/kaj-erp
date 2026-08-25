import 'package:quality_line_erp/core/models/model_value_reader.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.roleId,
    required this.roleName,
    this.jobTitle = '',
    required this.passwordHash,
    this.avatarBase64,
    this.cloudAuthUid,
    this.authProvider = 'local',
    this.cloudEmailVerified = false,
    required this.isActive,
    required this.createdAt,
    this.lastLoginAt,
    this.updatedAt,
  });

  final String id;
  final String username;
  final String fullName;
  final String email;
  final String phone;
  final String roleId;
  final String roleName;
  final String jobTitle;
  final String passwordHash;
  final String? avatarBase64;
  final String? cloudAuthUid;
  final String authProvider;
  final bool cloudEmailVerified;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final DateTime? updatedAt;

  UserModel copyWith({
    String? username,
    String? fullName,
    String? email,
    String? phone,
    String? roleId,
    String? roleName,
    String? jobTitle,
    String? passwordHash,
    String? avatarBase64,
    bool clearAvatar = false,
    String? cloudAuthUid,
    bool clearCloudAuthUid = false,
    String? authProvider,
    bool? cloudEmailVerified,
    bool? isActive,
    DateTime? lastLoginAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      roleId: roleId ?? this.roleId,
      roleName: roleName ?? this.roleName,
      jobTitle: jobTitle ?? this.jobTitle,
      passwordHash: passwordHash ?? this.passwordHash,
      avatarBase64: clearAvatar ? null : avatarBase64 ?? this.avatarBase64,
      cloudAuthUid: clearCloudAuthUid
          ? null
          : cloudAuthUid ?? this.cloudAuthUid,
      authProvider: authProvider ?? this.authProvider,
      cloudEmailVerified: cloudEmailVerified ?? this.cloudEmailVerified,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'roleId': roleId,
      'jobTitle': jobTitle,
      'passwordHash': passwordHash,
      'avatarBase64': avatarBase64,
      'cloudAuthUid': cloudAuthUid,
      'authProvider': authProvider,
      'cloudEmailVerified': cloudEmailVerified ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: ModelValueReader.string(map, 'id'),
      username: ModelValueReader.string(map, 'username'),
      fullName: ModelValueReader.string(map, 'fullName'),
      email: ModelValueReader.string(map, 'email'),
      phone: ModelValueReader.string(map, 'phone'),
      roleId: ModelValueReader.string(map, 'roleId'),
      roleName: ModelValueReader.string(map, 'roleName'),
      jobTitle: ModelValueReader.string(map, 'jobTitle'),
      passwordHash: ModelValueReader.string(map, 'passwordHash'),
      avatarBase64: ModelValueReader.nullableString(map, 'avatarBase64'),
      cloudAuthUid: ModelValueReader.nullableString(map, 'cloudAuthUid'),
      authProvider: ModelValueReader.string(
        map,
        'authProvider',
        fallback: 'local',
      ),
      cloudEmailVerified: ModelValueReader.boolean(map, 'cloudEmailVerified'),
      isActive: ModelValueReader.boolean(map, 'isActive'),
      createdAt: ModelValueReader.requiredDateTime(
        map,
        'createdAt',
        aliases: const ['updatedAt', 'lastLoginAt', '_cloudUpdatedAt'],
      ),
      lastLoginAt: ModelValueReader.dateTime(map, 'lastLoginAt'),
      updatedAt: ModelValueReader.dateTime(map, 'updatedAt'),
    );
  }
}
