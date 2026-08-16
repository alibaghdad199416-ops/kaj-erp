import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

class AppUserAvatar extends StatelessWidget {
  const AppUserAvatar({
    super.key,
    required this.avatarBase64,
    required this.fallbackText,
    this.radius = 18,
    this.onTap,
  });

  final String? avatarBase64;
  final String fallbackText;
  final double radius;
  final VoidCallback? onTap;

  static Uint8List? decode(String? value) {
    if (value == null) return null;
    var normalized = value.trim();
    if (normalized.isEmpty) return null;
    final comma = normalized.indexOf(',');
    if (normalized.startsWith('data:image') && comma >= 0) {
      normalized = normalized.substring(comma + 1);
    }
    normalized = normalized.replaceAll(RegExp(r'\s+'), '');
    try {
      return base64Decode(normalized);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = decode(avatarBase64);
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: bytes == null ? null : MemoryImage(bytes),
      child: bytes == null
          ? AppText(
              _initials(fallbackText),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: radius * .65,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
    final callback = onTap;
    if (callback == null) {
      return Semantics(
        label: context.l10n.isArabic ? 'صورة المستخدم' : 'User avatar',
        image: true,
        child: avatar,
      );
    }
    return Semantics(
      label: AppTranslation.translate('تعديل الملف الشخصي'),
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius * 2),
        onTap: callback,
        child: avatar,
      ),
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'QL';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }
}
